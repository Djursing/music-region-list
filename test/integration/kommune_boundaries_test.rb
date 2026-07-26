# frozen_string_literal: true

require "test_helper"

class KommuneBoundariesTest < ActionDispatch::IntegrationTest
  test "serves the boundary file without requiring sign-in" do
    # The map fetches this before any trip context exists, and it is public
    # geographic data either way.
    get kommuner_boundaries_path

    assert_response :success
    assert_equal "application/geo+json", response.media_type
  end

  test "is cacheable and revalidates with an ETag" do
    # This is 1.7 MB; re-downloading it on every trip page view would be the
    # single largest cost in the app.
    get kommuner_boundaries_path

    assert response.headers["ETag"].present?
    assert_includes response.headers["Cache-Control"], "public"

    get kommuner_boundaries_path, headers: { "If-None-Match" => response.headers["ETag"] }
    assert_response :not_modified
  end

  test "the payload is the 98 kommuner the index knows about" do
    get kommuner_boundaries_path

    parsed = JSON.parse(response.body)
    codes = parsed["features"].map { |f| f.dig("properties", "kode") }

    assert_equal 98, parsed["features"].size
    assert_equal Geo::KommuneIndex.instance.codes.sort, codes.sort
  end
end
