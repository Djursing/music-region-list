# frozen_string_literal: true

require "test_helper"

module Trips
  class PositionResolverTest < ActiveSupport::TestCase
    setup do
      @account = spotify_account
      playlist = @account.playlists.create!(spotify_id: "p1", import_status: "imported")
      artist = Artist.create!(spotify_id: "a1", name: "Artist")
      playlist.playlist_artists.create!(artist: artist, track_count: 1)
      @trip = @account.trips.create!(playlist: playlist)
    end

    def record(lat:, lon:, ago: 0, speed: nil, heading: nil)
      @trip.trip_locations.create!(
        latitude: lat, longitude: lon, speed: speed, heading: heading,
        accuracy: 5, recorded_at: ago.seconds.ago
      )
    end

    test "returns nil when the phone has never reported" do
      assert_nil PositionResolver.new(@trip).call
    end

    test "a recent fix is used directly" do
      record(lat: 55.6761, lon: 12.5683, ago: 5)

      position = PositionResolver.new(@trip).call

      assert position.live?
      assert_equal "0101", position.kommune.kode
    end

    test "a stale fix is projected forward along the last heading" do
      # Sitting just west of the Copenhagen boundary heading east at 30 m/s.
      # After two minutes that is 3.6 km, which should carry us into the city.
      record(lat: 55.6761, lon: 12.4500, ago: 120, speed: 30.0, heading: 90.0)

      position = PositionResolver.new(@trip).call

      assert position.estimated?
      assert_operator position.longitude, :>, 12.4500, "should have moved east"
      assert_in_delta 55.6761, position.latitude, 0.01, "heading due east should barely change latitude"
    end

    test "projection covers the distance the speed implies" do
      record(lat: 56.0, lon: 10.0, ago: 60, speed: 30.0, heading: 0.0)

      position = PositionResolver.new(@trip).call

      # 30 m/s for 60 s is 1.8 km north, which is about 0.0162 degrees latitude.
      assert_in_delta 56.0162, position.latitude, 0.001
      assert_in_delta 10.0, position.longitude, 0.001
    end

    test "does not project when the car is barely moving" do
      # A stationary phone reports noisy headings; projecting along one would
      # invent movement that isn't happening.
      record(lat: 55.6761, lon: 12.5683, ago: 120, speed: 0.2, heading: 90.0)

      position = PositionResolver.new(@trip).call

      assert_equal :stale, position.source
      assert_equal 12.5683, position.longitude
    end

    test "does not project without a heading" do
      record(lat: 55.6761, lon: 12.5683, ago: 120, speed: 30.0, heading: nil)

      assert_equal :stale, PositionResolver.new(@trip).call.source
    end

    test "gives up projecting once the fix is too old to trust" do
      # Fifteen minutes at motorway speed is ~27 km — several kommuner of error.
      # An honest "unknown" beats a confident wrong answer.
      record(lat: 55.6761, lon: 12.5683, ago: 15.minutes.to_i, speed: 30.0, heading: 90.0)

      position = PositionResolver.new(@trip).call

      assert_equal :stale, position.source
      assert_nil position.kommune
      assert position.unknown?
    end

    test "uses the most recent fix, not the first" do
      record(lat: 55.6761, lon: 12.5683, ago: 60)   # Copenhagen
      record(lat: 56.1629, lon: 10.2039, ago: 5)    # Aarhus

      assert_equal "0751", PositionResolver.new(@trip).call.kommune.kode
    end

    test "a projection landing in the sea reports no kommune" do
      # Heading east out of Copenhagen ends up in Oresund.
      record(lat: 55.6761, lon: 12.6500, ago: 300, speed: 30.0, heading: 90.0)

      position = PositionResolver.new(@trip).call

      assert position.estimated?
      assert_nil position.kommune
    end
  end
end
