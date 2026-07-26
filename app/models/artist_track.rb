# frozen_string_literal: true

# One playable track credited to one artist.
#
# A track featuring two artists is stored twice, once per artist, so that
# whichever kommune you are in can find it by its own artist alone.
class ArtistTrack < ApplicationRecord
  PLAYLIST = "playlist"
  CATALOG = "catalog"
  SOURCES = [ PLAYLIST, CATALOG ].freeze

  belongs_to :artist
  belongs_to :playlist, optional: true

  validates :track_uri, presence: true, uniqueness: { scope: :artist_id }
  validates :source, inclusion: { in: SOURCES }

  # Playlist tracks are played first; the catalogue is only reached once an
  # artist's playlist tracks are used up during a trip.
  scope :from_playlist, -> { where(source: PLAYLIST) }
  scope :from_catalog, -> { where(source: CATALOG) }
end
