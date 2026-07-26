# frozen_string_literal: true

require "test_helper"

class DrivingTest < ActionDispatch::IntegrationTest
  setup do
    ENV["SPOTIFY_CLIENT_ID"] = "cid"
    ENV["SPOTIFY_CLIENT_SECRET"] = "csecret"
    @account = spotify_account(spotify_user_id: "oliver")
    sign_in_as(@account)

    @playlist = @account.playlists.create!(spotify_id: "p1", name: "Roadtrip",
                                           import_status: "imported", track_count: 40)
    12.times do |i|
      artist = Artist.create!(spotify_id: "a#{i}", name: "Artist #{i}")
      @playlist.playlist_artists.create!(artist: artist, track_count: 4)
      4.times do |t|
        ArtistTrack.create!(artist: artist, playlist: @playlist,
                            track_uri: "spotify:track:a#{i}-#{t}", track_name: "Song #{i}-#{t}",
                            source: ArtistTrack::PLAYLIST, duration_ms: 200_000)
      end
    end

    post playlist_trips_path(@playlist)
    @trip = Trip.sole
  end

  teardown do
    ENV.delete("SPOTIFY_CLIENT_ID")
    ENV.delete("SPOTIFY_CLIENT_SECRET")
  end

  test "posting a position resolves the kommune and its artist" do
    post trip_locations_path(@trip),
         params: { location: { latitude: 55.6761, longitude: 12.5683, speed: 12.0, heading: 90.0, accuracy: 8 } }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "København", body["kommune"]
    assert_equal "0101", body["kommune_kode"]
    assert_equal @trip.artist_for("0101").name, body["artist"]
    assert_equal "0101", @trip.reload.current_kommune_kode
  end

  test "starting a trip primes playback and hands over to the loop" do
    post trip_locations_path(@trip),
         params: { location: { latitude: 55.6761, longitude: 12.5683, accuracy: 8 } }

    play_stub = stub_request(:put, "https://api.spotify.com/v1/me/player/play")
      .to_return(status: 204)

    assert_enqueued_with(job: QueueNextTrackJob) do
      post trip_playback_path(@trip)
    end

    assert_requested play_stub
    @trip.reload
    assert @trip.active?
    assert_equal 1, @trip.trip_plays.count, "the seed track counts as played"
    assert_redirected_to drive_trip_path(@trip)
  end

  test "a trip can be restarted when its artist has only one track" do
    # A short playlist gives some artists a single track. Restarting the trip
    # picks that same track again, and recording it a second time used to
    # violate the (trip, artist_track) uniqueness and blow up with a 500.
    small = @account.playlists.create!(spotify_id: "tiny", name: "Tiny",
                                       import_status: "imported", track_count: 1)
    artist = Artist.create!(spotify_id: "solo", name: "Solo Artist")
    small.playlist_artists.create!(artist: artist, track_count: 1)
    ArtistTrack.create!(artist: artist, playlist: small, track_uri: "spotify:track:only",
                        track_name: "Only Song", source: ArtistTrack::PLAYLIST, duration_ms: 200_000)

    post playlist_trips_path(small)
    trip = Trip.last
    post trip_locations_path(trip),
         params: { location: { latitude: 55.6761, longitude: 12.5683, accuracy: 8 } }
    stub_request(:put, "https://api.spotify.com/v1/me/player/play").to_return(status: 204)

    post trip_playback_path(trip)
    assert trip.reload.active?
    assert_equal 1, trip.trip_plays.count

    delete trip_playback_path(trip)

    # The restart must not raise; the single track is simply replayed.
    post trip_playback_path(trip)

    assert_response :redirect
    assert trip.reload.active?
    assert_equal 1, trip.trip_plays.count, "a replayed track should not be recorded twice"
  end

  test "starting without a position tells the driver why" do
    post trip_playback_path(@trip)

    assert_redirected_to drive_trip_path(@trip)
    assert_match(/waiting for your location/i, flash[:alert])
    assert_not @trip.reload.active?
  end

  test "starting with no active Spotify device explains the fix" do
    post trip_locations_path(@trip), params: { location: { latitude: 55.6761, longitude: 12.5683, accuracy: 8 } }
    stub_request(:put, "https://api.spotify.com/v1/me/player/play")
      .to_return(status: 404, body: { error: { message: "No active device found" } }.to_json,
                 headers: { "Content-Type" => "application/json" })

    post trip_playback_path(@trip)

    assert_match(/play something in spotify first/i, flash[:alert])
  end

  test "the driving screen states the background-location limit plainly" do
    get drive_trip_path(@trip)

    assert_response :success
    # This is the app's one real limitation; the driver should not have to
    # discover it on a motorway.
    assert_select "details", text: /no way to read position in the background/i
    assert_select "[data-controller='driving']"
  end

  def stub_playing(uri: "spotify:track:playing")
    stub_spotify(:get, "/me/player", body: {
      "is_playing" => true, "progress_ms" => 30_000,
      "item" => { "uri" => uri, "duration_ms" => 200_000 }
    })
  end

  # Captures the track URIs handed to PUT /me/player/play.
  def stub_play(collector)
    stub_request(:put, "https://api.spotify.com/v1/me/player/play")
      .to_return do |req|
        collector.concat(JSON.parse(req.body)["uris"])
        { status: 204 }
      end
  end

  test "skipping plays a replacement outright" do
    # Deliberately not "queue then advance": Spotify's queue cannot be inspected
    # reliably or edited, and advancing twice to get past a duplicate raced the
    # player badly enough to stop the music.
    trip = active_trip_at(55.6761, 12.5683)
    stub_playing
    played = []
    play_stub = stub_play(played)

    post skip_trip_playback_path(trip)

    assert_requested play_stub, times: 1
    assert_equal 1, played.size
    assert_nil trip.reload.queued_for_track_uri
    assert_nil trip.last_queued_track_uri, "nothing is queued behind a track played directly"
    assert_enqueued_with(job: QueueNextTrackJob)
  end

  test "skipping never plays the song being skipped" do
    trip = active_trip_at(55.6761, 12.5683)
    artist = trip.artist_for("0101")
    playing = artist.artist_tracks.first
    stub_playing(uri: playing.track_uri)
    played = []
    stub_play(played)

    post skip_trip_playback_path(trip)

    assert_equal 1, played.size
    refute_equal playing.track_uri, played.first, "skip replayed the very song being skipped"
  end

  test "skipping does not touch the queue endpoints at all" do
    # No stubs for /me/player/queue or /me/player/next are registered, so any
    # request to them would raise. Skip must not depend on queue state.
    trip = active_trip_at(55.6761, 12.5683)
    stub_playing
    stub_play([])

    post skip_trip_playback_path(trip)

    assert_response :redirect
  end

  test "skipping fetches the artist's catalogue when the playlist is thin" do
    # "Skip" means another song by this artist, not another playlist track. With
    # one playlist track by them there is nothing to move to until the wider
    # catalogue is fetched, so it happens inline rather than in the background.
    trip = active_trip_at(55.6761, 12.5683)
    artist = trip.artist_for("0101")
    artist.artist_tracks.where.not(id: artist.artist_tracks.first.id).delete_all
    artist.update!(catalog_synced_at: nil)
    playing = artist.artist_tracks.sole
    refute artist.catalog_synced?

    stub_playing(uri: playing.track_uri)
    stub_request(:get, "https://api.spotify.com/v1/artists/#{artist.spotify_id}/albums")
      .with(query: hash_including({}))
      .to_return(status: 200, body: { "items" => [ { "id" => "alb1", "name" => "Album" } ], "next" => nil }.to_json,
                 headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://api.spotify.com/v1/albums/alb1/tracks")
      .with(query: hash_including({}))
      .to_return(status: 200, body: { "items" => [ {
        "id" => "deep", "uri" => "spotify:track:deepcut", "name" => "Deep Cut",
        "duration_ms" => 200_000, "artists" => [ { "id" => artist.spotify_id } ]
      } ], "next" => nil }.to_json, headers: { "Content-Type" => "application/json" })

    played = []
    stub_play(played)

    post skip_trip_playback_path(trip)

    assert_equal [ "spotify:track:deepcut" ], played,
                 "skip should play the catalogue track it just fetched"
    assert artist.reload.catalog_synced?
  end

  test "skipping with nothing playing says so instead of failing" do
    trip = active_trip_at(55.6761, 12.5683)
    stub_spotify(:get, "/me/player", status: 204)

    post skip_trip_playback_path(trip)

    assert_match(/nothing is playing/i, flash[:alert])
  end

  test "the drive screen offers skip only while the trip is running" do
    trip = active_trip_at(55.6761, 12.5683)

    get drive_trip_path(trip)
    assert_select "form[action='#{skip_trip_playback_path(trip)}']"

    trip.update!(status: Trip::FINISHED)
    get drive_trip_path(trip)
    assert_select "form[action='#{skip_trip_playback_path(trip)}']", count: 0
  end

  test "stopping finishes the trip" do
    @trip.update!(status: Trip::ACTIVE, started_at: Time.current)

    delete trip_playback_path(@trip)

    assert @trip.reload.finished?
  end

  test "a drive across the country changes kommune and artist" do
    # Walks the same route the development simulate_drive tool uses, through the
    # same endpoint the phone posts to. Copenhagen to Aarhus in under a second,
    # rather than four hours on the E45.
    route = [
      [ 55.6761, 12.5683 ],  # København
      [ 55.6415, 12.0803 ],  # Roskilde
      [ 55.3900, 11.3500 ],  # Slagelse
      [ 55.3128, 10.7893 ],  # Nyborg
      [ 55.4038, 10.4024 ],  # Odense
      [ 55.7100,  9.5400 ],  # Vejle
      [ 56.1629, 10.2039 ]   # Aarhus
    ]

    visited = route.filter_map do |lat, lon|
      post trip_locations_path(@trip),
           params: { location: { latitude: lat, longitude: lon, speed: 30.0, heading: 270.0, accuracy: 8 } }
      assert_response :success
      JSON.parse(response.body).values_at("kommune_kode", "artist")
    end

    codes = visited.map(&:first)
    assert_equal 7, codes.compact.size, "every waypoint should land in a kommune"
    assert_equal codes, codes.uniq, "each waypoint is a different kommune"

    # With 12 artists over 98 kommuner, a cross-country drive should hear
    # several different ones rather than the same artist throughout.
    assert_operator visited.map(&:last).uniq.size, :>=, 4,
                    "expected the artist to change repeatedly, got #{visited.map(&:last).uniq.inspect}"
  end

  test "one account cannot post positions to another's trip" do
    other = spotify_account(spotify_user_id: "someone-else")
    sign_in_as(other)

    post trip_locations_path(@trip), params: { location: { latitude: 55.6761, longitude: 12.5683 } }
    assert_response :not_found
  end

  private

  # A trip already under way, with a recent fix at the given coordinates.
  #
  # Artists are marked as already crawled so skip does not reach for the
  # catalogue; the one test that cares about the crawl clears the flag itself.
  def active_trip_at(latitude, longitude)
    @trip.update!(status: Trip::ACTIVE, started_at: Time.current)
    @trip.trip_locations.create!(latitude: latitude, longitude: longitude,
                                 accuracy: 8, recorded_at: Time.current)
    Artist.update_all(catalog_synced_at: Time.current)
    @trip
  end

  def sign_in_as(account)
    get spotify_auth_path
    state = session[:spotify_oauth_state]
    stub_request(:post, Spotify::OAuth::TOKEN_URL)
      .to_return(status: 200, body: { access_token: "at", refresh_token: "rt", expires_in: 3600 }.to_json,
                 headers: { "Content-Type" => "application/json" })
    stub_spotify(:get, "/me", body: { "id" => account.spotify_user_id, "display_name" => account.display_name })
    get spotify_auth_callback_path, params: { code: "abc", state: state }
  end
end
