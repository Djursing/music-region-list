# frozen_string_literal: true

require "test_helper"

class DevRoutesTest < ActionDispatch::IntegrationTest
  test "the development sign-in bypass is not routable outside development" do
    # This route signs in as any account without touching Spotify. It exists
    # only so the app can be worked on without live credentials, and must never
    # be reachable anywhere else. DevController re-checks the environment too,
    # but the route simply not existing is the stronger guarantee.
    refute Rails.env.development?, "this test is meaningless if run in development"

    refute Rails.application.routes.routes.any? { |route|
      route.path.spec.to_s.include?("dev/sign_in")
    }, "the dev sign-in route is drawn outside development"

    # And it genuinely 404s rather than being merely unnamed.
    get "/dev/sign_in/anyone"
    assert_response :not_found
  end
end
