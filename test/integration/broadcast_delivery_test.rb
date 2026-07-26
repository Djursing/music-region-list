# frozen_string_literal: true

require "test_helper"

# Guards the two things that make server-pushed updates actually reach the page.
# Both failed silently in development: no error, no log, just a page that never
# changed.
class BroadcastDeliveryTest < ActionDispatch::IntegrationTest
  test "development does not use the in-process cable adapter" do
    # Everything this app broadcasts comes from a job in the separate bin/jobs
    # process, while the websocket lives in the web process. The async adapter
    # only delivers within one process, so those updates are dropped and the
    # page sits on "Importing…" forever.
    config = YAML.safe_load(Rails.root.join("config/cable.yml").read, aliases: true)

    assert_equal "solid_cable", config.dig("development", "adapter"),
                 "development must use a cross-process cable adapter"
    assert_equal "solid_cable", config.dig("production", "adapter")
  end

  test "starting a trip breaks out of the playlist frame" do
    ENV["SPOTIFY_CLIENT_ID"] = "cid"
    ENV["SPOTIFY_CLIENT_SECRET"] = "csecret"
    account = spotify_account(spotify_user_id: "oliver")
    sign_in_as(account)

    playlist = account.playlists.create!(spotify_id: "p1", name: "Roadtrip",
                                         import_status: "imported", track_count: 9)
    artist = Artist.create!(spotify_id: "a1", name: "Artist")
    playlist.playlist_artists.create!(artist: artist, track_count: 9)

    get playlist_path(playlist)
    assert_response :success

    # The button lives inside <turbo-frame id="playlist_N"> but navigates to the
    # trip page, which contains no such frame. Without targeting _top, Turbo
    # replaces the panel with "Content missing".
    form = css_select("form[action='#{playlist_trips_path(playlist)}']").first
    assert form.present?, "expected a Start a trip button"
    assert_equal "_top", form["data-turbo-frame"],
                 "Start a trip must target _top or Turbo renders 'Content missing'"
  ensure
    ENV.delete("SPOTIFY_CLIENT_ID")
    ENV.delete("SPOTIFY_CLIENT_SECRET")
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
end
