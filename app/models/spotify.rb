# frozen_string_literal: true

module Spotify
  class Error < StandardError; end

  # The refresh token is gone or was revoked. Spotify began expiring refresh
  # tokens six months after the original authorisation in June 2026, so this is
  # expected roughly twice a year rather than being an exceptional condition.
  # The only cure is sending the user back through the OAuth flow.
  class ReauthorizationRequired < Error; end

  # 403. Almost always means the account is not Premium — the playback queue
  # endpoints are Premium-only.
  class PremiumRequired < Error; end

  # No device is currently active, so there is nothing to queue onto. Happens
  # when Spotify has been idle long enough for the phone to drop off Connect.
  class NoActiveDevice < Error; end

  # 429. `retry_after` comes from the Retry-After header, in seconds.
  class RateLimited < Error
    attr_reader :retry_after

    def initialize(message = "Rate limited by Spotify", retry_after: nil)
      @retry_after = retry_after
      super(message)
    end
  end

  # Since February 2026 Spotify only returns the contents of playlists the user
  # owns or collaborates on. Everything else — editorial playlists like
  # "This Is …", algorithmic mixes, and other people's playlists — returns
  # metadata with no items at all.
  #
  # This is a flat restriction, not a permissions issue we can ask our way out
  # of, so it is surfaced as its own error with advice the UI can show verbatim.
  class PlaylistNotAccessible < Error
    def initialize(message = nil)
      super(message || "Spotify only exposes the contents of playlists you own or collaborate on. " \
                       "Make your own copy of this playlist in Spotify, then import that copy.")
    end
  end
end
