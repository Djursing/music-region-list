# frozen_string_literal: true

class PlaylistsController < ApplicationController
  before_action :set_playlist, only: %i[show destroy]

  def index
    @playlists = current_account.playlists.order(created_at: :desc)
    @playlist = current_account.playlists.new
  end

  def show
    @playlist_artists = @playlist.playlist_artists.includes(:artist).by_prominence
  end

  def create
    spotify_id = Spotify::PlaylistLink.parse!(params.require(:playlist)[:link])

    @playlist = current_account.playlists.find_or_initialize_by(spotify_id: spotify_id)
    @playlist.import_status = "pending"
    @playlist.import_error = nil
    @playlist.save!

    ImportPlaylistJob.perform_later(@playlist)

    redirect_to @playlist, notice: "Importing playlist…"
  rescue Spotify::PlaylistLink::InvalidLink => e
    @playlists = current_account.playlists.order(created_at: :desc)
    @playlist = current_account.playlists.new
    flash.now[:alert] = e.message
    render :index, status: :unprocessable_entity
  end

  def destroy
    if @playlist.destroy
      redirect_to playlists_path, notice: "Playlist removed."
    else
      # Trips depend on their playlist for zone swaps and track selection, so a
      # playlist with trips is kept rather than quietly taking them down with
      # it. Say which trips are in the way instead of failing with a 500.
      trip_count = @playlist.trips.count
      redirect_to playlists_path,
                  alert: "#{@playlist.display_name} is used by " \
                         "#{helpers.pluralize(trip_count, 'trip')}. Delete " \
                         "#{trip_count == 1 ? 'it' : 'them'} first, then remove the playlist."
    end
  end

  private

  def set_playlist
    @playlist = current_account.playlists.find(params[:id])
  end
end
