# frozen_string_literal: true

# Development-only helpers for exercising the app without a live Spotify
# connection.
#
# The routes for this controller are only drawn when Rails.env.development?
# (see config/routes.rb), and every action re-checks the environment here too —
# an authentication bypass is worth defending twice.
class DevController < ApplicationController
  allow_unauthenticated
  before_action :ensure_development!

  # Signs in as an existing account so pages behind auth can be opened while
  # working on them. Real sign-in always goes through Spotify.
  def sign_in_as
    account = SpotifyAccount.find_by!(spotify_user_id: params[:spotify_user_id])
    sign_in(account)
    redirect_to params[:return_to].presence || trips_path
  end

  private

  def ensure_development!
    raise ActionController::RoutingError, "Not available" unless Rails.env.development?
  end
end
