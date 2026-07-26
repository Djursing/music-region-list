ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

# No test should reach the real Spotify API. Anything unstubbed fails loudly
# rather than hanging on a network call or, worse, hitting a live account.
WebMock.disable_net_connect!(allow_localhost: true)

module ActiveSupport
  class TestCase
    # The driving loop is a chain of self-scheduling jobs, so most of what is
    # worth asserting is about what got enqueued and when.
    include ActiveJob::TestHelper
    # Deliberately serial. The suite runs in about three seconds; forking one
    # worker per core saves roughly one of those, and in exchange each worker
    # wants its own database. On a cold checkout all of them issue CREATE
    # DATABASE at once, Postgres serialises those against template1, and the
    # contention intermittently hangs or crashes the forked workers.
    #
    # Raise this once the suite is slow enough for the parallelism to pay for
    # itself, and pre-create the worker databases if it misbehaves.
    parallelize(workers: 1)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Builds an account with a valid, unexpired token so client tests exercise
    # the request path rather than the refresh path.
    def spotify_account(access_token: "test-access-token", expires_in: 3600, **attrs)
      SpotifyAccount.create!(
        spotify_user_id: "user-#{SecureRandom.hex(4)}",
        display_name: "Test User",
        access_token: access_token,
        refresh_token: "test-refresh-token",
        access_token_expires_at: expires_in && Time.current + expires_in,
        authorized_at: Time.current,
        **attrs
      )
    end

    def stub_spotify(method, path, status: 200, body: nil, headers: {}, query: nil)
      stub = stub_request(method, "https://api.spotify.com/v1#{path}")
      stub = stub.with(query: query) if query
      stub.to_return(
        status: status,
        body: body.nil? ? "" : body.to_json,
        headers: { "Content-Type" => "application/json" }.merge(headers)
      )
    end

    # Mirrors the post-February-2026 playlist items shape, where each element
    # exposes its track under `item` rather than `track`.
    def playlist_items_page(tracks, next_url: nil)
      {
        "href" => "https://api.spotify.com/v1/playlists/p1/items",
        "limit" => 100,
        "offset" => 0,
        "total" => tracks.size,
        "next" => next_url,
        "items" => tracks.map { |t| { "added_at" => "2026-01-01T00:00:00Z", "item" => t } }
      }
    end

    def spotify_track(id:, name:, artists:, album: "An Album", duration_ms: 210_000)
      {
        "id" => id,
        "type" => "track",
        "uri" => "spotify:track:#{id}",
        "name" => name,
        "duration_ms" => duration_ms,
        "album" => { "id" => "alb-#{id}", "name" => album },
        "artists" => artists.map { |a| { "id" => a[:id], "name" => a[:name], "uri" => "spotify:artist:#{a[:id]}" } }
      }
    end
  end
end
