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
end
