# frozen_string_literal: true

module Spotify
  # Extracts a playlist ID from whatever the user pasted.
  #
  # Spotify's own share menu produces at least three shapes depending on where
  # you copy from — the web player URL, the desktop "Copy Spotify URI" option,
  # and occasionally a bare ID — so all three are accepted. Share links also
  # carry a `?si=` tracking parameter that must be discarded.
  class PlaylistLink
    # Base62, and Spotify IDs are 22 characters today. The length is not
    # validated so that a future change in ID length doesn't break imports.
    ID_PATTERN = /\A[A-Za-z0-9]+\z/

    URL_PATTERN = %r{\Ahttps?://open\.spotify\.com/(?:intl-[a-z]{2}/)?playlist/([A-Za-z0-9]+)}
    URI_PATTERN = /\Aspotify:playlist:([A-Za-z0-9]+)\z/

    # Recognised so we can say *which* wrong thing was pasted rather than a
    # generic parse failure — pasting an album or artist link is an easy slip.
    WRONG_TYPE_URL = %r{\Ahttps?://open\.spotify\.com/(?:intl-[a-z]{2}/)?(album|track|artist|show|episode)/}
    WRONG_TYPE_URI = /\Aspotify:(album|track|artist|show|episode):/

    class InvalidLink < StandardError; end

    def self.parse!(input)
      value = input.to_s.strip
      raise InvalidLink, "Paste a Spotify playlist link." if value.empty?

      if (match = value.match(URL_PATTERN) || value.match(URI_PATTERN))
        return match[1]
      end

      if (wrong = value.match(WRONG_TYPE_URL) || value.match(WRONG_TYPE_URI))
        raise InvalidLink, "That is a Spotify #{wrong[1]} link, not a playlist link."
      end

      return value if value.match?(ID_PATTERN)

      raise InvalidLink, "That does not look like a Spotify playlist link."
    end

    def self.parse(input)
      parse!(input)
    rescue InvalidLink
      nil
    end
  end
end
