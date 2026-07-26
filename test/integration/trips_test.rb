# frozen_string_literal: true

require "test_helper"

class TripsTest < ActionDispatch::IntegrationTest
  setup do
    ENV["SPOTIFY_CLIENT_ID"] = "cid"
    ENV["SPOTIFY_CLIENT_SECRET"] = "csecret"
    @account = spotify_account(spotify_user_id: "oliver")
    sign_in_as(@account)
    @playlist = imported_playlist(artist_count: 12)
  end

  teardown do
    ENV.delete("SPOTIFY_CLIENT_ID")
    ENV.delete("SPOTIFY_CLIENT_SECRET")
  end

  test "starting a trip fills every kommune" do
    assert_difference -> { Trip.count }, 1 do
      post playlist_trips_path(@playlist)
    end

    trip = Trip.sole
    assert_redirected_to trip
    assert_equal 98, trip.zone_assignments.count
    assert_equal Geo::KommuneIndex.instance.codes.sort,
                 trip.zone_assignments.pluck(:kommune_kode).sort
  end

  test "excluded artists stay off the map" do
    excluded = @playlist.playlist_artists.first
    excluded.update!(excluded: true)

    post playlist_trips_path(@playlist)

    assert_not_includes Trip.sole.zone_assignments.pluck(:artist_id), excluded.artist_id
  end

  test "a playlist with every artist excluded cannot start a trip" do
    @playlist.playlist_artists.update_all(excluded: true)

    assert_no_difference -> { Trip.count } do
      post playlist_trips_path(@playlist)
    end

    assert_redirected_to playlist_path(@playlist)
    assert_match(/nobody to put on the map/i, flash[:alert])
  end

  test "re-rolling produces a different map without changing zone count" do
    post playlist_trips_path(@playlist)
    trip = Trip.sole
    before = trip.zone_assignments.pluck(:kommune_kode, :artist_id).to_h

    patch trip_path(trip)

    after = trip.reload.zone_assignments.pluck(:kommune_kode, :artist_id).to_h
    assert_equal 98, after.size
    refute_equal before, after, "a re-roll should rearrange the map"
  end

  test "the trip page reports artist spread and any silent borders" do
    post playlist_trips_path(@playlist)

    get trip_path(Trip.sole)

    assert_response :success
    assert_select "h1", text: /Trip of/
    # 12 artists colours the Danish map cleanly, so no warning should appear.
    assert_select "div", text: /won't change the music/, count: 0
  end

  test "warns about silent borders when the pool is too small" do
    small = imported_playlist(artist_count: 2, spotify_id: "p-small")

    post playlist_trips_path(small)
    get trip_path(Trip.last)

    assert_response :success
    assert_select "div", text: /won't change the music/
  end

  test "a zone's artist can be swapped by kommune code" do
    post playlist_trips_path(@playlist)
    trip = Trip.sole
    replacement = @playlist.available_artists.where.not(id: trip.artist_for("0101").id).first

    patch trip_zone_path(trip, "0101"), params: { artist_id: replacement.id }

    assert_equal replacement.id, trip.reload.artist_for("0101").id
  end

  test "a zone cannot be given an artist from outside the trip's pool" do
    post playlist_trips_path(@playlist)
    trip = Trip.sole
    stranger = Artist.create!(spotify_id: "outsider", name: "Not In Playlist")

    patch trip_zone_path(trip, "0101"), params: { artist_id: stranger.id }

    assert_response :not_found
  end

  test "one account cannot see or re-roll another's trip" do
    post playlist_trips_path(@playlist)
    trip = Trip.sole

    other = spotify_account(spotify_user_id: "someone-else")
    sign_in_as(other)

    get trip_path(trip)
    assert_response :not_found

    patch trip_path(trip)
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

  def imported_playlist(artist_count:, spotify_id: "p1")
    playlist = @account.playlists.create!(
      spotify_id: spotify_id, name: "Roadtrip", import_status: "imported", track_count: artist_count
    )
    artist_count.times do |i|
      artist = Artist.find_or_create_by!(spotify_id: "a#{i}") { |a| a.name = "Artist #{i}" }
      playlist.playlist_artists.create!(artist: artist, track_count: 3)
    end
    playlist
  end
end
