# frozen_string_literal: true

class Trip < ApplicationRecord
  DRAFT = "draft"
  ACTIVE = "active"
  FINISHED = "finished"
  STATUSES = [ DRAFT, ACTIVE, FINISHED ].freeze

  belongs_to :spotify_account
  belongs_to :playlist

  has_many :zone_assignments, dependent: :delete_all
  has_many :trip_plays, dependent: :delete_all
  has_many :trip_locations, dependent: :delete_all

  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: ACTIVE) }

  def draft? = status == DRAFT
  def active? = status == ACTIVE
  def finished? = status == FINISHED

  def display_name
    name.presence || "Trip of #{created_at.to_date.to_fs(:long)}"
  end

  # Begins the drive: primes Spotify with one track so the queue has something
  # to attach to, then hands over to the self-scheduling loop.
  def start!(seed_position: nil)
    kode = seed_position&.kommune&.kode || current_kommune_kode || trip_locations.most_recent.first&.to_kommune&.kode
    raise Trips::NoPositionYet if kode.nil?

    artist = artist_for(kode)
    choice = Trips::TrackChooser.new(self, artist).call
    raise Trips::NoTracksAvailable if choice.nil?

    spotify_account.client.start_playback(uris: choice.track.track_uri)

    transaction do
      update!(status: ACTIVE, started_at: Time.current, current_kommune_kode: kode,
              idle_since: nil, last_error: nil, queued_for_track_uri: nil,
              last_queued_track_uri: choice.track.track_uri)
      record_play(artist: artist, choice: choice, kommune_kode: kode)
    end

    QueueNextTrackJob.set(wait: 5.seconds).perform_later(self)
    broadcast_hud
    choice
  end

  # Records that a track was queued, so it is not chosen again later in the trip.
  #
  # A repeat is not recorded: it is already in the history, and re-inserting it
  # would violate the (trip, artist_track) uniqueness. That happens easily on a
  # short playlist — an artist with a single track hits it the moment the trip is
  # restarted. `find_or_create_by` covers the same collision arriving from two
  # directions at once.
  def record_play(artist:, choice:, kommune_kode:)
    return if choice.repeat?

    trip_plays.find_or_create_by!(artist_track_id: choice.track.id) do |play|
      play.artist = artist
      play.kommune_kode = kommune_kode
      play.queued_at = Time.current
    end
  end

  # Moves on from the current song at the driver's request.
  #
  # The queue-ahead loop only puts a track in Spotify's queue in the last
  # seconds of the one playing, so for most of a song Spotify's queue is empty
  # and skipping would stop playback rather than advance it. So a track for the
  # current kommune is queued first, then skipped to — which also means the
  # replacement comes from wherever the car is now, not from where it was when
  # the previous track was chosen.
  def skip!
    client = spotify_account.client
    state = client.playback_state
    raise Trips::NotPlaying if state.nil?

    current_uri = state.dig("item", "uri")
    kode = Trips::PositionResolver.new(self).call&.kommune&.kode || current_kommune_kode
    raise Trips::NoPositionYet if kode.nil?

    # Only queue if the loop has not already done so for this track, otherwise
    # the skip would jump over a track that was never heard.
    if queued_for_track_uri != current_uri
      artist = artist_for(kode)
      choice = Trips::TrackChooser.new(self, artist).call
      raise Trips::NoTracksAvailable if choice.nil?

      client.enqueue(choice.track.track_uri)
      record_play(artist: artist, choice: choice, kommune_kode: kode)
      update!(last_queued_track_uri: choice.track.track_uri)
    end

    client.skip_to_next

    # What was queued is now playing, so the loop has to queue afresh for it.
    update!(current_kommune_kode: kode, queued_for_track_uri: nil, last_error: nil)
    QueueNextTrackJob.set(wait: 3.seconds).perform_later(self)
    broadcast_hud
  end

  def stop!
    update!(status: FINISHED, ended_at: Time.current)
    broadcast_hud
  end

  def current_kommune
    Geo::KommuneIndex.instance.find(current_kommune_kode) if current_kommune_kode
  end

  def current_artist = current_kommune_kode && artist_for(current_kommune_kode)

  def last_queued_track
    ArtistTrack.find_by(track_uri: last_queued_track_uri) if last_queued_track_uri
  end

  # Pushed to the driving screen whenever the loop changes anything, so the
  # phone receives updates only when something actually happened rather than
  # polling for four hours.
  def broadcast_hud
    Turbo::StreamsChannel.broadcast_replace_to(
      self,
      target: "trip_hud",
      partial: "trips/hud",
      locals: { trip: self, position: Trips::PositionResolver.new(self).call }
    )
  end

  # Deals the playlist's artists across every kommune. Called on creation and
  # again whenever the user asks for a different arrangement, since the map is
  # re-rolled per trip rather than being a fixed musical geography.
  def assign_zones!(random: Random.new)
    artist_ids = playlist.available_artists.pluck(:id)
    index = Geo::KommuneIndex.instance

    result = Trips::ZoneAssigner.new(
      artist_ids: artist_ids,
      kommune_codes: index.codes,
      adjacency: index.codes.index_with { |kode| index.neighbours(kode) },
      random: random
    ).call

    rows = result.assignments.map do |kommune_kode, artist_id|
      { trip_id: id, kommune_kode: kommune_kode, artist_id: artist_id,
        created_at: Time.current, updated_at: Time.current }
    end

    transaction do
      zone_assignments.delete_all
      ZoneAssignment.insert_all!(rows)
    end

    result
  end

  def artist_for(kommune_kode)
    zone_assignments.includes(:artist).find_by(kommune_kode: kommune_kode)&.artist
  end

  # Zones whose artist also owns a bordering kommune, so crossing that border
  # would not change the music. Surfaced in the UI because it is the one thing
  # a small artist pool visibly costs you.
  def silent_borders
    index = Geo::KommuneIndex.instance
    by_kode = zone_assignments.pluck(:kommune_kode, :artist_id).to_h

    by_kode.count do |kode, artist_id|
      index.neighbours(kode).any? { |neighbour| by_kode[neighbour] == artist_id }
    end
  end

  def artist_zone_counts
    zone_assignments.joins(:artist).group("artists.name").count
  end

  # Stable ordering by artist id, so a zone swap or a page reload never
  # recolours the rest of the map.
  def artist_palette
    Trips::Palette.for(zone_assignments.distinct.order(:artist_id).pluck(:artist_id))
  end

  # kommune_kode => { artist name, colour } — everything the map needs to paint
  # itself, kept separate from the geometry so the 1.7 MB boundary file can be
  # cached once and reused across every trip.
  def map_zones
    palette = artist_palette

    zone_assignments.includes(:artist).to_h do |assignment|
      [ assignment.kommune_kode,
        { artist_id: assignment.artist_id,
          artist: assignment.artist.name,
          color: palette[assignment.artist_id] } ]
    end
  end
end
