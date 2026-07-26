# frozen_string_literal: true

module Trips
  # Picks the next track to queue for whichever kommune the car is in.
  #
  # Songs from the imported playlist come first: the driver chose those, so they
  # should be heard before anything dug out of an artist's back catalogue. Only
  # once an artist's playlist tracks are used up does the pool widen.
  #
  # Exhaustion is tracked per (trip, artist) rather than per kommune. An artist
  # re-used across two kommuner shares one pool, so arriving in their second
  # zone doesn't replay the song you heard in the first.
  class TrackChooser
    Choice = Struct.new(:track, :tier, :exhausted, keyword_init: true) do
      # :playlist  — from the imported playlist
      # :catalog   — from the artist's wider catalogue
      # :repeat    — nothing unplayed left; replaying the oldest rather than
      #              letting the car fall silent
      def repeat? = tier == :repeat
    end

    def initialize(trip, artist, random: Random.new)
      @trip = trip
      @artist = artist
      @random = random
    end

    def call
      return nil if @artist.nil?

      played_ids = @trip.trip_plays.for_artist(@artist).pluck(:artist_track_id)

      if (track = sample(unplayed(ArtistTrack::PLAYLIST, played_ids)))
        return Choice.new(track: track, tier: :playlist, exhausted: false)
      end

      if (track = sample(unplayed(ArtistTrack::CATALOG, played_ids)))
        return Choice.new(track: track, tier: :catalog, exhausted: false)
      end

      # Nothing unplayed anywhere. Falling silent would be worse than a repeat,
      # so replay whatever has been waiting longest — and report exhaustion so
      # the caller can kick off a catalogue crawl for next time.
      oldest = @trip.trip_plays.for_artist(@artist).order(:queued_at).first
      return nil if oldest.nil?

      Choice.new(track: oldest.artist_track, tier: :repeat, exhausted: true)
    end

    # True when this artist has nothing left that hasn't been played and their
    # catalogue has never been fetched — the signal to crawl it.
    def needs_catalog?
      return false if @artist.nil? || @artist.catalog_synced?

      played_ids = @trip.trip_plays.for_artist(@artist).pluck(:artist_track_id)
      unplayed(ArtistTrack::PLAYLIST, played_ids).none?
    end

    private

    def unplayed(source, played_ids)
      scope = @artist.artist_tracks.where(source: source)
      played_ids.any? ? scope.where.not(id: played_ids) : scope
    end

    def sample(scope)
      ids = scope.pluck(:id)
      return nil if ids.empty?

      ArtistTrack.find(ids.sample(random: @random))
    end
  end
end
