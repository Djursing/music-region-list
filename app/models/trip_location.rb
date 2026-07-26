# frozen_string_literal: true

# A position reported by the phone during a trip.
#
# `speed` (metres/second) and `heading` (degrees clockwise from true north) come
# straight from the browser Geolocation API and are frequently null when the
# device is stationary. They matter because the server dead-reckons from the
# most recent fix once the phone is locked and stops reporting.
class TripLocation < ApplicationRecord
  belongs_to :trip

  validates :latitude, :longitude, :recorded_at, presence: true

  scope :most_recent, -> { order(recorded_at: :desc) }

  def to_kommune
    Geo::KommuneIndex.instance.lookup(lat: latitude.to_f, lon: longitude.to_f)
  end

  def stale?(as_of: Time.current, threshold: 30.seconds)
    recorded_at < as_of - threshold
  end
end
