# frozen_string_literal: true

class TripsController < ApplicationController
  before_action :set_trip, only: %i[show drive update destroy]

  def index
    @trips = current_account.trips.includes(:playlist).order(created_at: :desc)
  end

  def show
    @zone_assignments = @trip.zone_assignments.includes(:artist).to_a
    @artist_counts = @trip.artist_zone_counts.sort_by { |_, count| -count }
    @silent_borders = @trip.silent_borders
  end

  # The screen used in the car: big current-kommune readout, and the only place
  # that reports position.
  def drive
    @position = Trips::PositionResolver.new(@trip).call
  end

  def create
    playlist = current_account.playlists.imported.find(params[:playlist_id])

    # A trip without zone assignments is useless, so the two are committed
    # together — otherwise an empty artist pool leaves an orphaned trip behind.
    trip = Trip.transaction do
      current_account.trips.create!(playlist: playlist, name: params[:name].presence).tap(&:assign_zones!)
    end

    redirect_to trip, notice: "Dealt #{playlist.available_artists.count} artists across the map."
  rescue Trips::ZoneAssigner::NoArtistsAvailable
    redirect_to playlist_path(params[:playlist_id]),
                alert: "Every artist on this playlist is excluded, so there is nobody to put on the map."
  end

  # Re-roll: the map is meant to differ from trip to trip.
  def update
    @trip.assign_zones!
    redirect_to @trip, notice: "Re-rolled the map."
  end

  def destroy
    @trip.destroy!
    redirect_to trips_path, notice: "Trip deleted."
  end

  private

  def set_trip
    @trip = current_account.trips.find(params[:id])
  end
end
