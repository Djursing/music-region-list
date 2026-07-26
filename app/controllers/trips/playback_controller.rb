# frozen_string_literal: true

module Trips
  # Starts and stops the drive.
  class PlaybackController < ApplicationController
    before_action :set_trip

    def create
      @trip.start!
      redirect_to drive_trip_path(@trip), notice: "Playing. Keep this screen open for the sharpest positioning."
    rescue Trips::NoPositionYet
      redirect_to drive_trip_path(@trip),
                  alert: "Waiting for your location — allow location access, then try again."
    rescue Trips::NoTracksAvailable
      redirect_to drive_trip_path(@trip),
                  alert: "This kommune's artist has no playable tracks."
    rescue Spotify::NoActiveDevice
      redirect_to drive_trip_path(@trip),
                  alert: "Spotify has no active device. Play something in Spotify first, then start."
    rescue Spotify::PremiumRequired => e
      redirect_to drive_trip_path(@trip), alert: e.message
    end

    def destroy
      @trip.stop!
      redirect_to @trip, notice: "Trip finished."
    end

    private

    def set_trip
      @trip = current_account.trips.find(params[:trip_id])
    end
  end
end
