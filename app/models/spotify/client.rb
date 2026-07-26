# frozen_string_literal: true

module Spotify
  # Thin wrapper over the handful of Web API endpoints this app needs.
  #
  # Written by hand rather than using `rspotify`, whose last release (October
  # 2024) predates the February 2026 API overhaul: it still calls
  # `/playlists/{id}/tracks` and `/artists/{id}/top-tracks`, both of which were
  # removed. Those are precisely the endpoints this app lives on.
  #
  # Every request refreshes the access token first if it is close to expiry, and
  # retries once on a 401 in case the token died mid-flight.
  class Client
    API_BASE = "https://api.spotify.com/v1"
    PAGE_SIZE = 50
    PLAYLIST_PAGE_SIZE = 100

    def initialize(account)
      @account = account
    end

    # --- Profile ------------------------------------------------------------

    def me = get("/me")

    # --- Playlists ----------------------------------------------------------

    def playlist(playlist_id)
      get("/playlists/#{playlist_id}")
    end

    # Yields each playlist item hash. Note the February 2026 shape: the paging
    # object's elements expose the track under `item`, not `track`.
    #
    # Raises PlaylistNotAccessible when Spotify withholds the contents, which it
    # does for any playlist the user neither owns nor collaborates on.
    def playlist_items(playlist_id)
      return enum_for(:playlist_items, playlist_id) unless block_given?

      offset = 0
      loop do
        page = get("/playlists/#{playlist_id}/items",
                   limit: PLAYLIST_PAGE_SIZE, offset: offset)

        # A playlist we may not read comes back without an items array at all,
        # rather than with an empty one or an error status.
        raise PlaylistNotAccessible if page.nil? || !page.key?("items")

        entries = page["items"] || []
        entries.each do |entry|
          track = entry["item"]
          next if track.nil?            # removed/unavailable tracks appear as null
          next if track["type"] == "episode"  # podcasts have no artists to map

          yield track
        end

        break if entries.size < PLAYLIST_PAGE_SIZE
        offset += PLAYLIST_PAGE_SIZE
        break if page["next"].nil?
      end
    end

    # --- Catalogue ----------------------------------------------------------

    def artist(artist_id) = get("/artists/#{artist_id}")

    def artist_albums(artist_id, include_groups: "album,single")
      paginate("/artists/#{artist_id}/albums", include_groups: include_groups)
    end

    def album_tracks(album_id)
      paginate("/albums/#{album_id}/tracks")
    end

    # --- Playback -----------------------------------------------------------

    # Returns nil when nothing is playing: Spotify answers 204 No Content
    # rather than a 200 with null fields.
    def playback_state = get("/me/player")

    # Pushes a track onto the end of the queue. There is no counterpart to
    # remove one, which is why callers queue as late as they safely can.
    def enqueue(track_uri)
      post("/me/player/queue", uri: track_uri)
      true
    end

    def start_playback(uris:)
      put("/me/player/play", body: { uris: Array(uris) })
      true
    end

    private

    attr_reader :account

    def paginate(path, **params)
      return enum_for(:paginate, path, **params) unless block_given?

      offset = 0
      loop do
        page = get(path, **params, limit: PAGE_SIZE, offset: offset)
        entries = page&.dig("items") || []
        entries.each { |entry| yield entry }

        break if entries.size < PAGE_SIZE || page["next"].nil?
        offset += PAGE_SIZE
      end
    end

    def get(path, **params) = request(:get, path, params: params)
    def post(path, **params) = request(:post, path, params: params)
    def put(path, body: nil, **params) = request(:put, path, params: params, body: body)

    def request(method, path, params: {}, body: nil, retried: false)
      account.refresh_access_token_if_needed!

      response = connection.public_send(method, API_BASE + path) do |req|
        req.params.update(params.compact) if params.present?
        req.headers["Authorization"] = "Bearer #{account.access_token}"
        if body
          req.headers["Content-Type"] = "application/json"
          req.body = body.to_json
        end
      end

      handle(response, method, path, params: params, body: body, retried: retried)
    end

    def handle(response, method, path, params:, body:, retried:)
      case response.status
      when 200, 201
        response.body
      when 202, 204
        # 204 is both "queued successfully" and "nothing is playing", depending
        # on the endpoint. Returning nil lets callers treat absence uniformly.
        nil
      when 401
        # Token rejected despite our expiry check — clock skew, or it was
        # revoked. Force a refresh and try once more before giving up.
        raise ReauthorizationRequired, "Spotify rejected the access token twice" if retried

        account.refresh_access_token!
        request(method, path, params: params, body: body, retried: true)
      when 403
        raise PremiumRequired, spotify_message(response) ||
                               "Spotify refused the request; the account is probably not Premium"
      when 404
        # On player endpoints a 404 means "no active device", which is a normal
        # state (Spotify idle), not a missing resource.
        raise NoActiveDevice, "No active Spotify device" if path.start_with?("/me/player")

        raise Error, "Spotify resource not found: #{path}"
      when 429
        raise RateLimited.new(retry_after: response.headers["retry-after"]&.to_i)
      else
        raise Error, "Spotify request failed (#{response.status} #{method.to_s.upcase} #{path}): " \
                     "#{spotify_message(response) || response.body}"
      end
    end

    def spotify_message(response)
      body = response.body
      return nil unless body.is_a?(Hash)

      body.dig("error", "message") || body["error_description"]
    end

    def connection
      @connection ||= Faraday.new do |f|
        f.response :json, content_type: /\bjson$/
        f.options.timeout = 15
        f.options.open_timeout = 5
      end
    end
  end
end
