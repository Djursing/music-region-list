# frozen_string_literal: true

module Authentication
  extend ActiveSupport::Concern

  included do
    helper_method :current_account, :signed_in?
    before_action :require_account
  end

  class_methods do
    def allow_unauthenticated(**options)
      skip_before_action :require_account, **options
    end
  end

  private

  def current_account
    return @current_account if defined?(@current_account)

    @current_account = session[:spotify_account_id] && SpotifyAccount.find_by(id: session[:spotify_account_id])
  end

  def signed_in? = current_account.present?

  def require_account
    return if signed_in?

    redirect_to root_path, alert: "Connect your Spotify account to continue."
  end

  def sign_in(account)
    reset_session
    session[:spotify_account_id] = account.id
    @current_account = account
  end

  def sign_out
    reset_session
    @current_account = nil
  end
end
