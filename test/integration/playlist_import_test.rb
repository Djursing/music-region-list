# frozen_string_literal: true

require "test_helper"

class PlaylistImportTest < ActionDispatch::IntegrationTest
  setup do
    ENV["SPOTIFY_CLIENT_ID"] = "cid"
    ENV["SPOTIFY_CLIENT_SECRET"] = "csecret"
    @account = spotify_account(spotify_user_id: "oliver")
    sign_in_as(@account)
  end

  teardown do
    ENV.delete("SPOTIFY_CLIENT_ID")
    ENV.delete("SPOTIFY_CLIENT_SECRET")
  end

  test "submitting a playlist link enqueues an import" do
    assert_enqueued_with(job: ImportPlaylistJob) do
      post playlists_path, params: { playlist: { link: "https://open.spotify.com/playlist/abc123?si=x" } }
    end

    playlist = @account.playlists.sole
    assert_equal "abc123", playlist.spotify_id
    assert_redirected_to playlist
  end

  test "a bad link is reported without enqueueing anything" do
    assert_no_enqueued_jobs do
      post playlists_path, params: { playlist: { link: "https://open.spotify.com/album/abc123" } }
    end

    assert_response :unprocessable_entity
    assert_match(/album/i, flash[:alert])
  end

  test "re-submitting the same playlist reuses the record rather than duplicating" do
    2.times do
      post playlists_path, params: { playlist: { link: "spotify:playlist:abc123" } }
    end

    assert_equal 1, @account.playlists.count
  end

  test "the import screen lists artists with their track counts" do
    playlist = build_imported_playlist

    get playlist_path(playlist)

    assert_response :success
    assert_select "li", text: /Suspekt/
    assert_select "li", text: /2 tracks/
    assert_select "li", text: /Guest/
    assert_select "li", text: /1 track\b/
  end

  test "an artist can be excluded from the pool and restored" do
    playlist = build_imported_playlist
    link = playlist.playlist_artists.joins(:artist).find_by(artists: { name: "Guest" })

    patch playlist_artist_path(playlist, link)
    assert link.reload.excluded?
    assert_not_includes playlist.available_artists.pluck(:name), "Guest"

    patch playlist_artist_path(playlist, link)
    assert_not link.reload.excluded?
    assert_includes playlist.available_artists.pluck(:name), "Guest"
  end

  test "a failed import shows the reason" do
    playlist = @account.playlists.create!(
      spotify_id: "p9", import_status: "failed",
      import_error: "Spotify only exposes the contents of playlists you own or collaborate on."
    )

    get playlist_path(playlist)

    assert_response :success
    assert_select "p", text: /playlists you own or collaborate on/
  end

  test "a playlist with no trips can be removed" do
    playlist = build_imported_playlist

    assert_difference -> { Playlist.count }, -1 do
      delete playlist_path(playlist)
    end
    assert_redirected_to playlists_path
  end

  test "removing a playlist a trip depends on is refused, not a 500" do
    # Trips need their playlist for zone swaps and track selection, so the
    # association restricts deletion. That refusal must read as a message, not
    # blow up with RecordNotDestroyed.
    playlist = build_imported_playlist
    @account.trips.create!(playlist: playlist)

    assert_no_difference -> { Playlist.count } do
      delete playlist_path(playlist)
    end

    assert_redirected_to playlists_path
    assert_match(/used by 1 trip/i, flash[:alert])
    assert_match(/delete it first/i, flash[:alert])
  end

  test "one account cannot see another's playlists" do
    other = spotify_account(spotify_user_id: "someone-else")
    theirs = other.playlists.create!(spotify_id: "secret", import_status: "imported")

    # Scoped through current_account, so another user's playlist is simply not
    # found rather than merely hidden from the view.
    get playlist_path(theirs)
    assert_response :not_found

    patch playlist_artist_path(theirs, 1)
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

  def build_imported_playlist
    playlist = @account.playlists.create!(
      spotify_id: "p1", name: "Roadtrip", import_status: "imported", track_count: 3
    )
    suspekt = Artist.create!(spotify_id: "a1", name: "Suspekt")
    guest = Artist.create!(spotify_id: "a2", name: "Guest")
    playlist.playlist_artists.create!(artist: suspekt, track_count: 2)
    playlist.playlist_artists.create!(artist: guest, track_count: 1)
    playlist
  end
end
