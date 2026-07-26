# frozen_string_literal: true

module Trips
  # Swaps one kommune's artist. Driven by clicking a zone once the map exists;
  # until then it is reachable from the trip's zone list.
  class ZonesController < ApplicationController
    def update
      trip = current_account.trips.find(params[:trip_id])
      @zone = trip.zone_assignments.find_by!(kommune_kode: params[:id])
      artist = trip.playlist.available_artists.find(params[:artist_id])

      @zone.update!(artist: artist)

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to trip, notice: "#{@zone.kommune_name} now plays #{artist.name}." }
      end
    end
  end
end
