# frozen_string_literal: true

require "test_helper"

class SpotifyAuthFlowTest < ActionDispatch::IntegrationTest
  # Spotify::OAuth prefers these over credentials, which is also how they are
  # supplied on Railway, so tests configure the app the same way production does.
  setup do
    ENV["SPOTIFY_CLIENT_ID"] = "cid"
    ENV["SPOTIFY_CLIENT_SECRET"] = "csecret"
  end

  teardown do
    ENV.delete("SPOTIFY_CLIENT_ID")
    ENV.delete("SPOTIFY_CLIENT_SECRET")
  end

  test "signing in redirects to Spotify with the requested scopes" do
    get spotify_auth_path

    assert_response :redirect
    location = response.headers["Location"]
    assert location.start_with?("https://accounts.spotify.com/authorize")

    params = Rack::Utils.parse_query(URI.parse(location).query)
    assert_equal "cid", params["client_id"]
    assert_equal "code", params["response_type"]
    assert_includes params["scope"], "user-modify-playback-state"
    assert_includes params["scope"], "user-read-playback-state"
    assert params["state"].present?, "state is required to prevent a forged callback"
  end

  test "the sign-in link opts out of Turbo" do
    # OAuth redirects to accounts.spotify.com. Turbo follows redirects with
    # fetch, and a cross-origin redirect cannot be followed that way — it fails
    # as a CORS error with nothing useful on screen. The link has to trigger a
    # real browser navigation.
    get root_path

    assert_response :success
    link = css_select("a[href='#{spotify_auth_path}']").first
    assert link.present?, "expected a sign-in link on the home page"
    assert_equal "false", link["data-turbo"],
                 "sign-in must bypass Turbo or the redirect to Spotify fails as CORS"
  end

  test "a callback with a mismatched state is rejected" do
    get spotify_auth_path  # establishes a state in the session

    get spotify_auth_callback_path, params: { code: "abc", state: "not-the-state" }

    assert_redirected_to root_path
    assert_match(/expired/i, flash[:alert])
    assert_nil session[:spotify_account_id]
  end

  test "a callback with no prior state is rejected" do
    get spotify_auth_callback_path, params: { code: "abc", state: "anything" }

    assert_redirected_to root_path
    assert_nil session[:spotify_account_id]
  end

  test "a successful callback creates the account and signs in" do
    get spotify_auth_path
    state = session[:spotify_oauth_state]

    stub_request(:post, Spotify::OAuth::TOKEN_URL)
      .to_return(status: 200,
                 body: { access_token: "at", refresh_token: "rt", expires_in: 3600 }.to_json,
                 headers: { "Content-Type" => "application/json" })
    stub_spotify(:get, "/me", body: { "id" => "oliver", "display_name" => "Oliver" })

    get spotify_auth_callback_path, params: { code: "abc", state: state }

    assert_redirected_to playlists_path
    account = SpotifyAccount.find_by(spotify_user_id: "oliver")
    assert account.present?
    assert_equal account.id, session[:spotify_account_id]
    assert_equal "rt", account.refresh_token
  end

  test "a user who declines on Spotify's screen gets a readable message" do
    get spotify_auth_path
    state = session[:spotify_oauth_state]

    get spotify_auth_callback_path, params: { error: "access_denied", state: state }

    assert_redirected_to root_path
    assert_match(/cancelled/i, flash[:alert])
  end

  test "signing out clears the session" do
    account = spotify_account
    post_sign_in(account)

    delete spotify_sign_out_path

    assert_redirected_to root_path
    assert_nil session[:spotify_account_id]
  end

  test "protected pages redirect when not signed in" do
    get playlists_path
    assert_redirected_to root_path
  end

  private

  def post_sign_in(account)
    get spotify_auth_path
    state = session[:spotify_oauth_state]
    stub_request(:post, Spotify::OAuth::TOKEN_URL)
      .to_return(status: 200, body: { access_token: "at", refresh_token: "rt", expires_in: 3600 }.to_json,
                 headers: { "Content-Type" => "application/json" })
    stub_spotify(:get, "/me", body: { "id" => account.spotify_user_id, "display_name" => account.display_name })
    get spotify_auth_callback_path, params: { code: "abc", state: state }
  end
end
