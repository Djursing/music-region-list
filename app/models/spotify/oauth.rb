# frozen_string_literal: true

module Spotify
  # The Spotify Authorization Code flow, hand-rolled.
  #
  # The `omniauth-spotify` gem is deliberately not used: its last release
  # predates the February 2026 API changes and it reads `/me` fields such as
  # `email`, `country` and `product` that no longer exist. The flow itself is
  # about fifty lines, so owning it is cheaper than tracking an unmaintained
  # dependency.
  class OAuth
    AUTHORIZE_URL = "https://accounts.spotify.com/authorize"
    TOKEN_URL = "https://accounts.spotify.com/api/token"

    # user-modify-playback-state — push tracks into the queue, start playback
    # user-read-playback-state  — read progress_ms so we know when to queue
    # playlist-read-private     — read the user's own (non-public) playlists
    # playlist-read-collaborative — and collaborative ones they are part of
    #
    # Note there is no `user-read-email`/`user-read-private`: those fields were
    # removed from /me in February 2026, so requesting them buys nothing.
    SCOPES = %w[
      user-modify-playback-state
      user-read-playback-state
      playlist-read-private
      playlist-read-collaborative
    ].freeze

    class << self
      def authorize_url(state:, redirect_uri:)
        params = {
          client_id: client_id,
          response_type: "code",
          redirect_uri: redirect_uri,
          scope: SCOPES.join(" "),
          state: state
        }
        "#{AUTHORIZE_URL}?#{params.to_query}"
      end

      # Exchanges the one-time code from the callback for an access/refresh pair.
      def exchange_code(code:, redirect_uri:)
        post_token(grant_type: "authorization_code", code: code, redirect_uri: redirect_uri)
      end

      # Spotify may or may not return a new refresh token on refresh. When it
      # does not, the caller must keep the existing one.
      def refresh(refresh_token:)
        post_token(grant_type: "refresh_token", refresh_token: refresh_token)
      end

      def client_id
        ENV["SPOTIFY_CLIENT_ID"].presence || Rails.application.credentials.dig(:spotify, :client_id)
      end

      def client_secret
        ENV["SPOTIFY_CLIENT_SECRET"].presence || Rails.application.credentials.dig(:spotify, :client_secret)
      end

      def configured? = client_id.present? && client_secret.present?

      private

      def post_token(**params)
        response = connection.post(TOKEN_URL, params)

        unless response.success?
          error = response.body.is_a?(Hash) ? response.body["error"] : nil

          # invalid_grant means the refresh token is expired or revoked. Since
          # June 2026 refresh tokens die six months after the original
          # authorisation, so this is a routine end-of-life, not a bug.
          raise ReauthorizationRequired, "Spotify rejected the grant (#{error})" if error == "invalid_grant"

          raise Error, "Spotify token request failed (#{response.status}: #{error || response.body})"
        end

        body = response.body
        {
          access_token: body.fetch("access_token"),
          refresh_token: body["refresh_token"],
          expires_in: body["expires_in"]&.to_i
        }
      end

      def connection
        @connection ||= Faraday.new do |f|
          f.request :url_encoded
          f.request :authorization, :basic, client_id, client_secret
          f.response :json, content_type: /\bjson$/
          f.options.timeout = 15
          f.options.open_timeout = 5
        end
      end
    end
  end
end
