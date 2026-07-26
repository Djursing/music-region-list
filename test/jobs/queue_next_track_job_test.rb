# frozen_string_literal: true

require "test_helper"

class QueueNextTrackJobTest < ActiveSupport::TestCase
  setup do
    @account = spotify_account
    @playlist = @account.playlists.create!(spotify_id: "p1", import_status: "imported")
    @artist = Artist.create!(spotify_id: "a1", name: "Suspekt")
    @playlist.playlist_artists.create!(artist: @artist, track_count: 3)
    3.times do |i|
      ArtistTrack.create!(artist: @artist, playlist: @playlist, track_uri: "spotify:track:#{i}",
                          track_name: "Track #{i}", source: ArtistTrack::PLAYLIST, duration_ms: 200_000)
    end

    @trip = @account.trips.create!(playlist: @playlist, status: Trip::ACTIVE, started_at: Time.current)
    # Every kommune belongs to the one artist, so any position works.
    ZoneAssignment.insert_all!(
      Geo::KommuneIndex.instance.codes.map do |kode|
        { trip_id: @trip.id, kommune_kode: kode, artist_id: @artist.id,
          created_at: Time.current, updated_at: Time.current }
      end
    )
    @trip.trip_locations.create!(latitude: 55.6761, longitude: 12.5683, recorded_at: Time.current, accuracy: 5)
  end

  def stub_playback(progress_ms:, duration_ms: 200_000, uri: "spotify:track:playing", playing: true)
    stub_spotify(:get, "/me/player", body: {
      "is_playing" => playing,
      "progress_ms" => progress_ms,
      "item" => { "uri" => uri, "duration_ms" => duration_ms }
    })
  end

  test "sleeps until just before the track ends rather than polling" do
    # 100s remaining, queue lead is 25s, so it should come back in ~75s. The
    # whole point of the design: one wake-up per track, not one every 10s.
    stub_playback(progress_ms: 100_000)

    assert_enqueued_with(job: QueueNextTrackJob) do
      QueueNextTrackJob.perform_now(@trip)
    end

    job = enqueued_jobs.last
    delay = job["scheduled_at"].to_time - Time.current
    assert_in_delta 75, delay, 3, "expected to sleep ~75s, slept #{delay.round}s"
    assert_equal 0, @trip.reload.trip_plays.count, "must not queue this early"
  end

  test "queues once the track is nearly over" do
    stub_playback(progress_ms: 185_000, uri: "spotify:track:playing")
    queue_stub = stub_request(:post, "https://api.spotify.com/v1/me/player/queue")
      .with(query: hash_including({}))
      .to_return(status: 204)

    QueueNextTrackJob.perform_now(@trip)

    assert_requested queue_stub
    assert_equal 1, @trip.reload.trip_plays.count
    assert_equal "spotify:track:playing", @trip.queued_for_track_uri
  end

  test "does not queue twice for the same playing track" do
    # Spotify has no way to remove a queued item, so a double-queue would be
    # audible and unrecoverable.
    @trip.update!(queued_for_track_uri: "spotify:track:playing")
    stub_playback(progress_ms: 190_000, uri: "spotify:track:playing")

    QueueNextTrackJob.perform_now(@trip)

    assert_equal 0, @trip.reload.trip_plays.count
    assert_enqueued_jobs 1, only: QueueNextTrackJob
  end

  test "queues again once the track has changed" do
    @trip.update!(queued_for_track_uri: "spotify:track:previous")
    stub_playback(progress_ms: 190_000, uri: "spotify:track:now")
    stub_request(:post, "https://api.spotify.com/v1/me/player/queue")
      .with(query: hash_including({})).to_return(status: 204)

    QueueNextTrackJob.perform_now(@trip)

    assert_equal 1, @trip.reload.trip_plays.count
    assert_equal "spotify:track:now", @trip.queued_for_track_uri
  end

  test "queues from the kommune the car is in" do
    aarhus_artist = Artist.create!(spotify_id: "a2", name: "Tessa")
    @playlist.playlist_artists.create!(artist: aarhus_artist, track_count: 1)
    aarhus_track = ArtistTrack.create!(artist: aarhus_artist, playlist: @playlist,
                                       track_uri: "spotify:track:aarhus", track_name: "Aarhus Song",
                                       source: ArtistTrack::PLAYLIST, duration_ms: 200_000)
    @trip.zone_assignments.find_by(kommune_kode: "0751").update!(artist: aarhus_artist)
    @trip.trip_locations.create!(latitude: 56.1629, longitude: 10.2039, recorded_at: Time.current, accuracy: 5)

    stub_playback(progress_ms: 190_000)
    queue_stub = stub_request(:post, "https://api.spotify.com/v1/me/player/queue")
      .with(query: { uri: aarhus_track.track_uri }).to_return(status: 204)

    QueueNextTrackJob.perform_now(@trip)

    assert_requested queue_stub
    assert_equal "0751", @trip.reload.current_kommune_kode
  end

  test "keeps playing from the last known kommune when position is unavailable" do
    # The phone is locked and the fix is too old to project from. Falling silent
    # would be worse than playing the previous kommune's artist.
    @trip.trip_locations.delete_all
    @trip.update!(current_kommune_kode: "0101")
    stub_playback(progress_ms: 190_000)
    queue_stub = stub_request(:post, "https://api.spotify.com/v1/me/player/queue")
      .with(query: hash_including({})).to_return(status: 204)

    QueueNextTrackJob.perform_now(@trip)

    assert_requested queue_stub
    assert_equal 1, @trip.reload.trip_plays.count
  end

  test "keeps checking back while playback is paused" do
    stub_playback(progress_ms: 0, playing: false)

    QueueNextTrackJob.perform_now(@trip)

    assert @trip.reload.idle_since.present?
    assert @trip.active?, "a pause at a services stop must not end the trip"
    assert_enqueued_jobs 1, only: QueueNextTrackJob
  end

  test "ends the trip after a long enough silence" do
    @trip.update!(idle_since: 45.minutes.ago)
    stub_playback(progress_ms: 0, playing: false)

    QueueNextTrackJob.perform_now(@trip)

    assert @trip.reload.finished?
    assert_enqueued_jobs 0, only: QueueNextTrackJob
  end

  test "backs off for as long as Spotify asks when rate limited" do
    stub_spotify(:get, "/me/player", status: 429, headers: { "Retry-After" => "12" })

    QueueNextTrackJob.perform_now(@trip)

    delay = enqueued_jobs.last["scheduled_at"].to_time - Time.current
    assert_in_delta 12, delay, 3
  end

  test "treats a missing device as idle rather than an error" do
    stub_spotify(:get, "/me/player", status: 404,
                 body: { "error" => { "message" => "No active device found" } })

    QueueNextTrackJob.perform_now(@trip)

    assert_match(/no active spotify device/i, @trip.reload.last_error)
    assert @trip.active?
    assert_enqueued_jobs 1, only: QueueNextTrackJob
  end

  test "ends the trip when the account turns out not to be Premium" do
    # Retrying cannot fix this, and the driver needs to be told.
    stub_spotify(:get, "/me/player", status: 403,
                 body: { "error" => { "message" => "Player command failed: Premium required" } })

    QueueNextTrackJob.perform_now(@trip)

    assert @trip.reload.finished?
    assert_match(/premium/i, @trip.last_error)
  end

  test "stops entirely once the trip is no longer active" do
    @trip.update!(status: Trip::FINISHED)

    QueueNextTrackJob.perform_now(@trip)

    assert_enqueued_jobs 0
  end

  test "asks for a catalogue crawl when the artist runs dry" do
    ArtistTrack.where(artist: @artist).limit(2).find_each do |t|
      @trip.trip_plays.create!(artist: @artist, artist_track: t, kommune_kode: "0101", queued_at: 1.minute.ago)
    end

    stub_playback(progress_ms: 190_000)
    stub_request(:post, "https://api.spotify.com/v1/me/player/queue")
      .with(query: hash_including({})).to_return(status: 204)

    assert_enqueued_with(job: CrawlCatalogJob) { QueueNextTrackJob.perform_now(@trip) }
  end
end
