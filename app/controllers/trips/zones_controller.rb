# frozen_string_literal: true

module Trips
  # The panel beside the map: shows which artist owns a kommune and swaps it.
  #
  # Zones are addressed by kommune code rather than record id, because that is
  # what the map hands back when a region is clicked.
  class ZonesController < ApplicationController
    before_action :set_trip
    before_action :set_zone

    def show
      @artists = pool
    end

    def update
      artist = pool.find(params[:artist_id])
      @zone.update!(artist: artist)
      @artists = pool

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @trip, notice: "#{@zone.kommune_name} now plays #{artist.name}." }
      end
    end

    private

    def set_trip
      @trip = current_account.trips.find(params[:trip_id])
    end

    def set_zone
      @zone = @trip.zone_assignments.includes(:artist).find_by!(kommune_kode: params[:id])
    end

    # Only artists from this trip's playlist, minus exclusions — a zone should
    # never be given someone who isn't part of the trip.
    def pool
      @trip.playlist.available_artists.order(:name)
    end

    helper_method :zone_color

    def zone_color(artist_id)
      @trip.artist_palette[artist_id] || "#3f3f46"
    end
  end
end
