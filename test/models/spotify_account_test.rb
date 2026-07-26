# frozen_string_literal: true

require "test_helper"

class SpotifyAccountTest < ActiveSupport::TestCase
  test "tokens are encrypted at rest" do
    account = spotify_account(access_token: "plaintext-secret")

    stored = SpotifyAccount.connection.select_value(
      "SELECT access_token FROM spotify_accounts WHERE id = #{account.id}"
    )

    refute_includes stored.to_s, "plaintext-secret"
    assert_equal "plaintext-secret", account.reload.access_token
  end

  test "treats a token close to expiry as already expired" do
    # Refreshing only once the token is truly dead risks a request landing just
    # after expiry, so anything inside the skew window counts as expired.
    assert spotify_account(expires_in: 30).access_token_expired?
    refute spotify_account(expires_in: 3600).access_token_expired?
    assert spotify_account(expires_in: nil).access_token_expired?
  end

  test "refreshing keeps the existing refresh token when Spotify omits a new one" do
    account = spotify_account
    original_refresh = account.refresh_token

    stub_request(:post, Spotify::OAuth::TOKEN_URL)
      .to_return(status: 200,
                 body: { access_token: "new-access", expires_in: 3600 }.to_json,
                 headers: { "Content-Type" => "application/json" })

    account.refresh_access_token!

    assert_equal "new-access", account.access_token
    assert_equal original_refresh, account.refresh_token,
                 "must not blank the refresh token when the response omits it"
  end

  test "refreshing stores a rotated refresh token when Spotify sends one" do
    account = spotify_account

    stub_request(:post, Spotify::OAuth::TOKEN_URL)
      .to_return(status: 200,
                 body: { access_token: "new-access", refresh_token: "rotated", expires_in: 3600 }.to_json,
                 headers: { "Content-Type" => "application/json" })

    account.refresh_access_token!
    assert_equal "rotated", account.refresh_token
  end

  test "invalid_grant surfaces as ReauthorizationRequired" do
    # Since June 2026 refresh tokens expire six months after the original
    # authorisation, so this is routine end-of-life rather than a failure.
    account = spotify_account

    stub_request(:post, Spotify::OAuth::TOKEN_URL)
      .to_return(status: 400,
                 body: { error: "invalid_grant", error_description: "Refresh token revoked" }.to_json,
                 headers: { "Content-Type" => "application/json" })

    assert_raises(Spotify::ReauthorizationRequired) { account.refresh_access_token! }
  end

  test "refreshing without a stored refresh token fails fast" do
    account = spotify_account
    account.update_column(:refresh_token, nil)

    assert_raises(Spotify::ReauthorizationRequired) { account.reload.refresh_access_token! }
  end

  test "reports when reauthorization is coming due" do
    fresh = spotify_account(authorized_at: Time.current)
    refute fresh.reauthorization_due_soon?
    assert_in_delta 6.months.from_now.to_i, fresh.reauthorization_due_at.to_i, 60

    stale = spotify_account(authorized_at: 5.months.ago - 3.weeks)
    assert stale.reauthorization_due_soon?
  end

  test "from_callback! creates then updates an account by spotify user id" do
    tokens = { access_token: "a1", refresh_token: "r1", expires_in: 3600 }
    profile = { "id" => "spotify-user", "display_name" => "Oliver" }

    account = SpotifyAccount.from_callback!(tokens: tokens, profile: profile)
    assert_equal "Oliver", account.display_name

    again = SpotifyAccount.from_callback!(
      tokens: { access_token: "a2", expires_in: 3600 }, profile: profile
    )

    assert_equal account.id, again.id, "should reuse the account for the same Spotify user"
    assert_equal "a2", again.access_token
    assert_equal "r1", again.refresh_token, "a callback without a refresh token must not clear it"
  end
end
