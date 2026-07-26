# frozen_string_literal: true

module Trips
  # Receives positions from the phone while the driving screen is open.
  class LocationsController < ApplicationController
    def create
      trip = current_account.trips.find(params[:trip_id])
      location = trip.trip_locations.create!(location_params.merge(recorded_at: Time.current))

      kommune = location.to_kommune

      # A border crossing is worth knowing about immediately, but the track for
      # it is not queued here — that happens near the end of the current song,
      # when the car's position is most likely to still be right.
      if kommune && kommune.kode != trip.current_kommune_kode
        trip.update!(current_kommune_kode: kommune.kode)
        trip.broadcast_hud
      end

      render json: {
        kommune: kommune&.navn,
        kommune_kode: kommune&.kode,
        artist: kommune && trip.artist_for(kommune.kode)&.name
      }
    end

    private

    def location_params
      params.expect(location: [ :latitude, :longitude, :speed, :heading, :accuracy ])
    end
  end
end
