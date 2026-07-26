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
