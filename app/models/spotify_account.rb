# frozen_string_literal: true

# A connected Spotify user. Doubles as the app's identity — with Development
# Mode capped at five test users there is no separate user model to justify.
class SpotifyAccount < ApplicationRecord
  # Tokens are the keys to someone's music account; encrypt them at rest.
  encrypts :access_token
  encrypts :refresh_token

  has_many :playlists, dependent: :destroy
  has_many :trips, dependent: :destroy

  validates :spotify_user_id, presence: true, uniqueness: true

  # Refreshed a little before the token actually dies, so a request that takes a
  # moment to reach Spotify doesn't arrive with an expired token.
  EXPIRY_SKEW = 60.seconds

  # Spotify expires refresh tokens six months after the *original*
  # authorisation — not six months after the last refresh — so the countdown
  # cannot be extended by staying active.
  REFRESH_TOKEN_LIFETIME = 6.months

  # Warn while there is still time to reconnect from the sofa rather than
  # discovering it somewhere on the E45.
  REAUTHORIZATION_WARNING_WINDOW = 2.weeks

  def self.from_callback!(tokens:, profile:)
    account = find_or_initialize_by(spotify_user_id: profile.fetch("id"))
    account.display_name = profile["display_name"]
    account.access_token = tokens.fetch(:access_token)
    account.refresh_token = tokens[:refresh_token] if tokens[:refresh_token].present?
    account.access_token_expires_at = expires_at_from(tokens[:expires_in])
    account.authorized_at = Time.current
    account.save!
    account
  end

  def access_token_expired?
    access_token_expires_at.nil? || access_token_expires_at <= Time.current + EXPIRY_SKEW
  end

  def refresh_access_token_if_needed!
    refresh_access_token! if access_token_expired?
  end

  def refresh_access_token!
    raise Spotify::ReauthorizationRequired, "No refresh token stored" if refresh_token.blank?

    tokens = Spotify::OAuth.refresh(refresh_token: refresh_token)

    update!(
      access_token: tokens.fetch(:access_token),
      # Spotify only sometimes rotates the refresh token; keep the old one when
      # the response omits it, or we would lock ourselves out.
      refresh_token: tokens[:refresh_token].presence || refresh_token,
      access_token_expires_at: self.class.expires_at_from(tokens[:expires_in])
    )

    access_token
  end

  def client = @client ||= Spotify::Client.new(self)

  def reauthorization_due_at
    authorized_at && authorized_at + REFRESH_TOKEN_LIFETIME
  end

  def reauthorization_due_soon?
    due = reauthorization_due_at
    due.present? && due <= Time.current + REAUTHORIZATION_WARNING_WINDOW
  end

  def self.expires_at_from(expires_in)
    expires_in.present? ? Time.current + expires_in.to_i.seconds : nil
  end
end
