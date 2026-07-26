# frozen_string_literal: true

require "test_helper"

module Trips
  class TrackChooserTest < ActiveSupport::TestCase
    setup do
      @account = spotify_account
      @playlist = @account.playlists.create!(spotify_id: "p1", import_status: "imported")
      @artist = Artist.create!(spotify_id: "a1", name: "Suspekt")
      @playlist.playlist_artists.create!(artist: @artist, track_count: 2)
      @trip = @account.trips.create!(playlist: @playlist)
    end

    def track(uri, source: ArtistTrack::PLAYLIST)
      ArtistTrack.create!(artist: @artist, playlist: @playlist, track_uri: uri,
                          track_name: uri, source: source, duration_ms: 200_000)
    end

    def mark_played(artist_track, kode: "0101", at: Time.current)
      @trip.trip_plays.create!(artist: @artist, artist_track: artist_track,
                               kommune_kode: kode, queued_at: at)
    end

    test "prefers playlist tracks over catalogue ones" do
      # The driver chose the playlist tracks, so they should be heard before
      # anything dug out of the back catalogue.
      catalog = track("spotify:track:cat", source: ArtistTrack::CATALOG)
      playlist = track("spotify:track:pl")

      choice = TrackChooser.new(@trip, @artist).call

      assert_equal playlist, choice.track
      assert_equal :playlist, choice.tier
      refute_equal catalog, choice.track
    end

    test "never repeats a track already played on this trip" do
      first = track("spotify:track:1")
      second = track("spotify:track:2")
      mark_played(first)

      assert_equal second, TrackChooser.new(@trip, @artist).call.track
    end

    test "widens to the catalogue once playlist tracks are used up" do
      played = track("spotify:track:1")
      catalog = track("spotify:track:cat", source: ArtistTrack::CATALOG)
      mark_played(played)

      choice = TrackChooser.new(@trip, @artist).call

      assert_equal catalog, choice.track
      assert_equal :catalog, choice.tier
    end

    test "replays the longest-waiting track rather than falling silent" do
      oldest = track("spotify:track:1")
      newest = track("spotify:track:2")
      mark_played(oldest, at: 1.hour.ago)
      mark_played(newest, at: 1.minute.ago)

      choice = TrackChooser.new(@trip, @artist).call

      assert choice.repeat?
      assert_equal oldest, choice.track, "should replay the one heard longest ago"
    end

    test "exhaustion is shared across kommuner that have the same artist" do
      # The point of tracking per (trip, artist) rather than per kommune: an
      # artist re-used in two zones must not replay their first song when you
      # reach the second.
      first = track("spotify:track:1")
      track("spotify:track:2")
      mark_played(first, kode: "0101")

      choice = TrackChooser.new(@trip, @artist).call

      refute_equal first, choice.track, "arriving in a second zone replayed the first song"
    end

    test "reports needing a catalogue crawl only when playlist tracks run out" do
      played = track("spotify:track:1")

      refute TrackChooser.new(@trip, @artist).needs_catalog?, "still has an unplayed playlist track"

      mark_played(played)
      assert TrackChooser.new(@trip, @artist).needs_catalog?
    end

    test "does not ask for a crawl that has already happened" do
      played = track("spotify:track:1")
      mark_played(played)
      @artist.update!(catalog_synced_at: Time.current)

      refute TrackChooser.new(@trip, @artist).needs_catalog?
    end

    test "returns nil for an artist with no tracks at all" do
      assert_nil TrackChooser.new(@trip, @artist).call
      assert_nil TrackChooser.new(@trip, nil).call
    end
  end
end
