# frozen_string_literal: true

# Join between an imported playlist and one of the artists credited on it.
class PlaylistArtist < ApplicationRecord
  belongs_to :playlist
  belongs_to :artist

  scope :included_in_pool, -> { where(excluded: false) }

  # Guest features tend to appear once. Surfacing them first on the import
  # screen makes them easy to drop before they get a kommune of their own.
  scope :by_prominence, -> { order(track_count: :desc, id: :asc) }
end
