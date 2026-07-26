class ApplicationController < ActionController::Base
  include Authentication

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # A refresh token that has reached its six-month lifetime is not an error the
  # user can debug — it just means signing in again — so it is handled globally
  # rather than in each controller.
  rescue_from Spotify::ReauthorizationRequired do
    sign_out
    redirect_to root_path, alert: "Your Spotify authorisation has expired. Please connect again."
  end
end
