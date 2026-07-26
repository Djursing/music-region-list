# frozen_string_literal: true

# A Spotify playlist that has been imported to seed the artist pool.
class Playlist < ApplicationRecord
  STATUSES = %w[pending importing imported failed].freeze

  belongs_to :spotify_account

  has_many :playlist_artists, dependent: :destroy
  has_many :artists, through: :playlist_artists
  has_many :artist_tracks, dependent: :nullify
  has_many :trips, dependent: :restrict_with_error

  validates :spotify_id, presence: true, uniqueness: { scope: :spotify_account_id }
  validates :import_status, inclusion: { in: STATUSES }

  scope :imported, -> { where(import_status: "imported") }

  # The artists actually available to a trip: everything extracted from the
  # playlist minus the ones the user excluded on the import screen.
  def available_artists
    artists.merge(PlaylistArtist.included_in_pool)
  end

  def pending? = import_status == "pending"
  def importing? = import_status == "importing"
  def imported? = import_status == "imported"
  def failed? = import_status == "failed"
  def in_progress? = pending? || importing?

  def display_name = name.presence || "Playlist #{spotify_id}"
end
