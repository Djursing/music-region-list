# frozen_string_literal: true

class SpotifyAuthController < ApplicationController
  allow_unauthenticated only: %i[create callback destroy]

  # Kicks off the Authorization Code flow.
  def create
    unless Spotify::OAuth.configured?
      return redirect_to root_path,
                         alert: "Spotify credentials are not configured. Add spotify.client_id and " \
                                "spotify.client_secret with `bin/rails credentials:edit`."
    end

    state = SecureRandom.urlsafe_base64(24)
    session[:spotify_oauth_state] = state

    redirect_to Spotify::OAuth.authorize_url(state: state, redirect_uri: callback_url),
                allow_other_host: true
  end

  def callback
    expected_state = session.delete(:spotify_oauth_state)

    # Guards against a forged callback signing the user into someone else's
    # Spotify account.
    if expected_state.blank? || !ActiveSupport::SecurityUtils.secure_compare(expected_state, params[:state].to_s)
      return redirect_to root_path, alert: "That sign-in attempt expired. Please try again."
    end

    if params[:error].present?
      return redirect_to root_path, alert: "Spotify sign-in was cancelled (#{params[:error]})."
    end

    tokens = Spotify::OAuth.exchange_code(code: params[:code], redirect_uri: callback_url)
    profile = Spotify::Client.new(TransientAccount.new(tokens[:access_token])).me

    account = SpotifyAccount.from_callback!(tokens: tokens, profile: profile)
    sign_in(account)

    redirect_to playlists_path, notice: "Connected as #{account.display_name.presence || account.spotify_user_id}."
  rescue Spotify::Error => e
    redirect_to root_path, alert: "Could not connect to Spotify: #{e.message}"
  end

  def destroy
    sign_out
    redirect_to root_path, notice: "Disconnected from Spotify."
  end

  private

  def callback_url = spotify_auth_callback_url

  # The profile has to be fetched before a SpotifyAccount exists, since the
  # account is keyed on the Spotify user ID that this call returns. This stands
  # in for an account just long enough to make that one request.
  class TransientAccount
    attr_reader :access_token

    def initialize(access_token) = @access_token = access_token
    def refresh_access_token_if_needed! = nil
    def refresh_access_token! = raise(Spotify::ReauthorizationRequired, "Token rejected during sign-in")
  end
end
