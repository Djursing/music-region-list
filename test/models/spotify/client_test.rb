# frozen_string_literal: true

require "test_helper"

module Spotify
  class ClientTest < ActiveSupport::TestCase
    setup do
      @account = spotify_account
      @client = @account.client
    end

    # --- Playlist reading ---------------------------------------------------

    test "reads playlist items using the post-2026 `item` key" do
      track = spotify_track(id: "t1", name: "Song", artists: [ { id: "a1", name: "Suspekt" } ])
      stub_spotify(:get, "/playlists/p1/items", body: playlist_items_page([ track ]))
        .with(query: hash_including({}))

      items = @client.playlist_items("p1").to_a

      assert_equal 1, items.size
      assert_equal "spotify:track:t1", items.first["uri"]
      assert_equal "Suspekt", items.first["artists"].first["name"]
    end

    test "paginates playlist items until a short page arrives" do
      first = Array.new(100) { |i| spotify_track(id: "t#{i}", name: "S#{i}", artists: [ { id: "a1", name: "A" } ]) }
      second = [ spotify_track(id: "last", name: "Last", artists: [ { id: "a1", name: "A" } ]) ]

      stub_request(:get, "https://api.spotify.com/v1/playlists/p1/items")
        .with(query: { limit: 100, offset: 0 })
        .to_return(status: 200, body: playlist_items_page(first, next_url: "https://api.spotify.com/next").to_json,
                   headers: { "Content-Type" => "application/json" })
      stub_request(:get, "https://api.spotify.com/v1/playlists/p1/items")
        .with(query: { limit: 100, offset: 100 })
        .to_return(status: 200, body: playlist_items_page(second).to_json,
                   headers: { "Content-Type" => "application/json" })

      assert_equal 101, @client.playlist_items("p1").to_a.size
    end

    test "raises PlaylistNotAccessible when Spotify withholds the contents" do
      # Playlists the user neither owns nor collaborates on come back as
      # metadata with no items array at all — not as a 403.
      stub_spotify(:get, "/playlists/curated/items",
                   body: { "name" => "This Is Suspekt", "owner" => { "id" => "spotify" } })
        .with(query: hash_including({}))

      assert_raises(PlaylistNotAccessible) { @client.playlist_items("curated").to_a }
    end

    test "skips episodes and removed tracks in a playlist" do
      page = {
        "items" => [
          { "item" => nil },
          { "item" => { "type" => "episode", "uri" => "spotify:episode:e1" } },
          { "item" => spotify_track(id: "t1", name: "Real", artists: [ { id: "a1", name: "A" } ]) }
        ],
        "next" => nil
      }
      stub_spotify(:get, "/playlists/p1/items", body: page).with(query: hash_including({}))

      items = @client.playlist_items("p1").to_a
      assert_equal 1, items.size
      assert_equal "spotify:track:t1", items.first["uri"]
    end

    # --- Playback -----------------------------------------------------------

    test "playback_state returns nil when nothing is playing" do
      # Spotify answers 204 rather than 200-with-nulls when idle.
      stub_spotify(:get, "/me/player", status: 204)
      assert_nil @client.playback_state
    end

    test "playback_state returns progress and duration when playing" do
      stub_spotify(:get, "/me/player", body: {
        "is_playing" => true,
        "progress_ms" => 100_000,
        "item" => { "uri" => "spotify:track:t1", "duration_ms" => 210_000 }
      })

      state = @client.playback_state
      assert state["is_playing"]
      assert_equal 110_000, state.dig("item", "duration_ms") - state["progress_ms"]
    end

    test "enqueue posts the track uri" do
      stub = stub_spotify(:post, "/me/player/queue", status: 204)
        .with(query: { uri: "spotify:track:t1" })

      assert @client.enqueue("spotify:track:t1")
      assert_requested stub
    end

    test "queueing without an active device raises NoActiveDevice" do
      stub_spotify(:post, "/me/player/queue", status: 404,
                   body: { "error" => { "status" => 404, "message" => "Player command failed: No active device found" } })
        .with(query: hash_including({}))

      assert_raises(NoActiveDevice) { @client.enqueue("spotify:track:t1") }
    end

    test "a 403 on playback is reported as PremiumRequired" do
      stub_spotify(:post, "/me/player/queue", status: 403,
                   body: { "error" => { "status" => 403, "message" => "Player command failed: Premium required" } })
        .with(query: hash_including({}))

      error = assert_raises(PremiumRequired) { @client.enqueue("spotify:track:t1") }
      assert_match(/premium/i, error.message)
    end

    # --- Failure handling ---------------------------------------------------

    test "429 raises RateLimited carrying Retry-After" do
      stub_spotify(:get, "/me/player", status: 429, headers: { "Retry-After" => "7" })

      error = assert_raises(RateLimited) { @client.playback_state }
      assert_equal 7, error.retry_after
    end

    test "a 401 triggers one refresh and a retry" do
      token_stub = stub_request(:post, Spotify::OAuth::TOKEN_URL)
        .to_return(status: 200,
                   body: { access_token: "refreshed-token", expires_in: 3600 }.to_json,
                   headers: { "Content-Type" => "application/json" })

      first = stub_request(:get, "https://api.spotify.com/v1/me")
        .with(headers: { "Authorization" => "Bearer test-access-token" })
        .to_return(status: 401, body: { error: { status: 401, message: "The access token expired" } }.to_json,
                   headers: { "Content-Type" => "application/json" })
      retry_stub = stub_request(:get, "https://api.spotify.com/v1/me")
        .with(headers: { "Authorization" => "Bearer refreshed-token" })
        .to_return(status: 200, body: { id: "user-1" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      assert_equal "user-1", @client.me["id"]
      assert_requested token_stub
      assert_requested first
      assert_requested retry_stub
      assert_equal "refreshed-token", @account.reload.access_token
    end

    test "a second 401 after refreshing gives up rather than looping" do
      stub_request(:post, Spotify::OAuth::TOKEN_URL)
        .to_return(status: 200, body: { access_token: "still-bad", expires_in: 3600 }.to_json,
                   headers: { "Content-Type" => "application/json" })
      stub_request(:get, "https://api.spotify.com/v1/me")
        .to_return(status: 401, body: { error: { message: "nope" } }.to_json,
                   headers: { "Content-Type" => "application/json" })

      assert_raises(ReauthorizationRequired) { @client.me }
    end

    # --- Catalogue ----------------------------------------------------------

    test "artist_albums and album_tracks paginate" do
      albums = Array.new(50) { |i| { "id" => "alb#{i}", "name" => "Album #{i}" } }
      stub_request(:get, "https://api.spotify.com/v1/artists/a1/albums")
        .with(query: { include_groups: "album,single", limit: 50, offset: 0 })
        .to_return(status: 200, body: { "items" => albums, "next" => "x" }.to_json,
                   headers: { "Content-Type" => "application/json" })
      stub_request(:get, "https://api.spotify.com/v1/artists/a1/albums")
        .with(query: { include_groups: "album,single", limit: 50, offset: 50 })
        .to_return(status: 200, body: { "items" => [ { "id" => "albX" } ], "next" => nil }.to_json,
                   headers: { "Content-Type" => "application/json" })

      assert_equal 51, @client.artist_albums("a1").to_a.size
    end
  end
end
