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
      trip_plays.create!(artist: artist, artist_track: choice.track,
                         kommune_kode: kode, queued_at: Time.current)
    end

    QueueNextTrackJob.set(wait: 5.seconds).perform_later(self)
    broadcast_hud
    choice
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
