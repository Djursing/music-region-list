# frozen_string_literal: true

require "test_helper"

class TripMapTest < ActionDispatch::IntegrationTest
  setup do
    ENV["SPOTIFY_CLIENT_ID"] = "cid"
    ENV["SPOTIFY_CLIENT_SECRET"] = "csecret"
    @account = spotify_account(spotify_user_id: "oliver")
    sign_in_as(@account)
    @playlist = imported_playlist(artist_count: 8)
    post playlist_trips_path(@playlist)
    @trip = Trip.sole
  end

  teardown do
    ENV.delete("SPOTIFY_CLIENT_ID")
    ENV.delete("SPOTIFY_CLIENT_SECRET")
  end

  test "the trip page hands the map every kommune with a colour" do
    get trip_path(@trip)
    assert_response :success

    zones = JSON.parse(css_select("[data-map-zones-value]").first["data-map-zones-value"])

    assert_equal 98, zones.size
    assert_equal Geo::KommuneIndex.instance.codes.sort, zones.keys.sort
    zones.each_value do |zone|
      assert_match(/\A#[0-9a-f]{6}\z/, zone["color"])
      assert zone["artist"].present?
    end
  end

  test "the map is pointed at the cacheable boundary endpoint, not given inline geometry" do
    get trip_path(@trip)

    element = css_select("[data-map-boundaries-url-value]").first
    assert_equal kommuner_boundaries_path, element["data-map-boundaries-url-value"]
    # The 1.7 MB geometry must not be inlined into the page.
    assert response.body.bytesize < 500_000, "trip page is #{response.body.bytesize} bytes"
  end

  test "one artist re-used across kommuner gets one colour everywhere" do
    zones = @trip.map_zones
    by_artist = zones.values.group_by { |z| z[:artist_id] }

    by_artist.each_value do |entries|
      assert_equal 1, entries.map { |e| e[:color] }.uniq.size
    end
    assert(by_artist.values.any? { |entries| entries.size > 1 }, "expected some artist re-use with 8 artists")
  end

  test "clicking a kommune loads its swap panel" do
    get trip_zone_path(@trip, "0101")

    assert_response :success
    assert_select "turbo-frame#zone_panel"
    assert_select "h3", text: "København"
  end

  test "swapping repaints the map, the panel and the list together" do
    replacement = @playlist.available_artists.where.not(id: @trip.artist_for("0101").id).first

    patch trip_zone_path(@trip, "0101"),
          params: { artist_id: replacement.id },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    streams = css_select("turbo-stream")
    targets = streams.map { |s| s["target"] }

    assert_includes targets, "zone_panel"
    assert_includes targets, "map_events"

    # Turbo cannot repaint a WebGL canvas, so the map is told out of band.
    broadcast = css_select("[data-controller='zone-broadcast']").first
    assert_equal "0101", broadcast["data-zone-broadcast-kode-value"]
    assert_equal replacement.name, broadcast["data-zone-broadcast-artist-value"]
    assert_match(/\A#[0-9a-f]{6}\z/, broadcast["data-zone-broadcast-color-value"])
  end

  test "a zone from another account's trip is not reachable" do
    other = spotify_account(spotify_user_id: "someone-else")
    sign_in_as(other)

    get trip_zone_path(@trip, "0101")
    assert_response :not_found
  end

  test "an unknown kommune code is not found rather than an error" do
    get trip_zone_path(@trip, "9999")
    assert_response :not_found
  end

  private

  def sign_in_as(account)
    get spotify_auth_path
    state = session[:spotify_oauth_state]
    stub_request(:post, Spotify::OAuth::TOKEN_URL)
      .to_return(status: 200, body: { access_token: "at", refresh_token: "rt", expires_in: 3600 }.to_json,
                 headers: { "Content-Type" => "application/json" })
    stub_spotify(:get, "/me", body: { "id" => account.spotify_user_id, "display_name" => account.display_name })
    get spotify_auth_callback_path, params: { code: "abc", state: state }
  end

  def imported_playlist(artist_count:)
    playlist = @account.playlists.create!(
      spotify_id: "p1", name: "Roadtrip", import_status: "imported", track_count: artist_count
    )
    artist_count.times do |i|
      artist = Artist.find_or_create_by!(spotify_id: "a#{i}") { |a| a.name = "Artist #{i}" }
      playlist.playlist_artists.create!(artist: artist, track_count: 3)
    end
    playlist
  end
end
