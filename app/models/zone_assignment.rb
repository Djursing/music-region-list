# frozen_string_literal: true

# One kommune's artist for the duration of one trip.
class ZoneAssignment < ApplicationRecord
  belongs_to :trip
  belongs_to :artist

  validates :kommune_kode, presence: true,
                           uniqueness: { scope: :trip_id },
                           format: { with: /\A\d{4}\z/ }

  def kommune = Geo::KommuneIndex.instance.find(kommune_kode)
  def kommune_name = kommune&.navn || kommune_kode
end
