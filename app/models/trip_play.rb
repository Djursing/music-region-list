# frozen_string_literal: true

# A track this trip has already queued.
#
# Exhaustion is tracked per (trip, artist) rather than per zone, so an artist
# re-used in two kommuner shares one pool — you should not hear the same song
# twice in a drive just because their second zone came up.
class TripPlay < ApplicationRecord
  belongs_to :trip
  belongs_to :artist
  belongs_to :artist_track

  validates :queued_at, presence: true

  scope :for_artist, ->(artist) { where(artist: artist) }
end
