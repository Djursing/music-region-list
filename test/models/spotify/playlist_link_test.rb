# frozen_string_literal: true

require "test_helper"

module Spotify
  class PlaylistLinkTest < ActiveSupport::TestCase
    ID = "37i9dQZF1DXcBWIGoYBM5M"

    test "accepts a share URL and discards the si tracking parameter" do
      assert_equal ID, PlaylistLink.parse!("https://open.spotify.com/playlist/#{ID}?si=abc123&pt=xyz")
    end

    test "accepts a localised share URL" do
      # Spotify inserts a locale segment for non-English users, e.g. /intl-da/.
      assert_equal ID, PlaylistLink.parse!("https://open.spotify.com/intl-da/playlist/#{ID}")
    end

    test "accepts the desktop app URI and a bare id" do
      assert_equal ID, PlaylistLink.parse!("spotify:playlist:#{ID}")
      assert_equal ID, PlaylistLink.parse!(ID)
    end

    test "tolerates surrounding whitespace and http" do
      assert_equal ID, PlaylistLink.parse!("  http://open.spotify.com/playlist/#{ID}  ")
    end

    test "names the wrong entity type rather than failing generically" do
      # Copying the wrong share link is an easy slip; saying which one was
      # pasted is far more useful than "invalid link".
      error = assert_raises(PlaylistLink::InvalidLink) do
        PlaylistLink.parse!("https://open.spotify.com/album/#{ID}")
      end
      assert_match(/album/, error.message)

      error = assert_raises(PlaylistLink::InvalidLink) { PlaylistLink.parse!("spotify:artist:#{ID}") }
      assert_match(/artist/, error.message)
    end

    test "rejects blank and unrelated input" do
      assert_raises(PlaylistLink::InvalidLink) { PlaylistLink.parse!("") }
      assert_raises(PlaylistLink::InvalidLink) { PlaylistLink.parse!("   ") }
      assert_raises(PlaylistLink::InvalidLink) { PlaylistLink.parse!(nil) }
      assert_raises(PlaylistLink::InvalidLink) { PlaylistLink.parse!("https://example.com/playlist/#{ID}") }
    end

    test "parse returns nil instead of raising" do
      assert_nil PlaylistLink.parse("not a link!")
      assert_equal ID, PlaylistLink.parse(ID)
    end
  end
end
