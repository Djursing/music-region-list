# frozen_string_literal: true

# Toggles whether an extracted artist takes part in zone assignment.
class PlaylistArtistsController < ApplicationController
  def update
    playlist = current_account.playlists.find(params[:playlist_id])
    @playlist_artist = playlist.playlist_artists.includes(:artist).find(params[:id])
    @playlist_artist.update!(excluded: !@playlist_artist.excluded)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to playlist }
    end
  end
end
