# frozen_string_literal: true

class Artist < ApplicationRecord
  has_many :artist_tracks, dependent: :destroy
  has_many :playlist_artists, dependent: :destroy
  has_many :playlists, through: :playlist_artists
  has_many :zone_assignments, dependent: :destroy

  validates :spotify_id, presence: true, uniqueness: true
  validates :name, presence: true

  # Null until the lazy catalogue crawl has run for this artist, which only
  # happens once a zone exhausts their playlist tracks mid-trip.
  def catalog_synced? = catalog_synced_at.present?

  def self.upsert_from_spotify!(payload)
    artist = find_or_initialize_by(spotify_id: payload.fetch("id"))
    artist.name = payload.fetch("name")
    artist.image_url ||= payload.dig("images", 0, "url")
    artist.save! if artist.changed?
    artist
  end
end
