# frozen_string_literal: true

require "test_helper"

module Geo
  class KommuneIndexTest < ActiveSupport::TestCase
    setup { @index = KommuneIndex.instance }

    test "loads exactly the 98 kommuner, excluding Christianso" do
      assert_equal 98, @index.kommuner.size
      # 0411 Christianso carries udenforkommuneinddeling=true in the DAWA source:
      # it belongs to no kommune and must not become an artist zone.
      assert_nil @index.find("0411")
    end

    test "resolves a city-centre point to its kommune" do
      # Radhuspladsen, Copenhagen
      assert_equal "0101", @index.lookup(lat: 55.6761, lon: 12.5683)&.kode
    end

    test "resolves points on islands that are separate polygons" do
      # Samso is an island: the kommune is a MultiPolygon whose mainland-adjacent
      # pieces are irrelevant. A single-Polygon implementation gets this wrong,
      # which is exactly why this test exists.
      assert_equal "0741", @index.lookup(lat: 55.8581, lon: 10.6140)&.kode

      # Bornholm, far east of the rest of the country.
      assert_equal "0400", @index.lookup(lat: 55.1000, lon: 14.7000)&.kode
    end

    test "resolves a spread of mainland cities" do
      {
        "0751" => [ 56.1629, 10.2039 ],  # Aarhus
        "0851" => [ 57.0488,  9.9187 ],  # Aalborg
        "0461" => [ 55.3959, 10.3883 ],  # Odense
        "0561" => [ 55.4680,  8.4520 ]   # Esbjerg
      }.each do |kode, (lat, lon)|
        assert_equal kode, @index.lookup(lat: lat, lon: lon)&.kode,
                     "expected #{kode} at #{lat},#{lon}"
      end
    end

    test "returns nil outside Denmark" do
      assert_nil @index.lookup(lat: 56.0000, lon: 11.0000)   # Kattegat, open sea
      assert_nil @index.lookup(lat: 52.5200, lon: 13.4050)   # Berlin
      assert_nil @index.lookup(lat: 59.3293, lon: 18.0686)   # Stockholm
    end

    test "bounding box prefilter never rejects a point the geometry accepts" do
      # Guards against a bbox that is too tight, which would silently make
      # lookups return nil for real locations.
      @index.kommuner.each do |k|
        min_x, min_y, max_x, max_y = k.bbox
        k.polygons.each do |polygon|
          polygon.first.each do |(x, y)|
            assert x >= min_x && x <= max_x, "#{k.kode}: vertex lon #{x} outside bbox"
            assert y >= min_y && y <= max_y, "#{k.kode}: vertex lat #{y} outside bbox"
          end
        end
      end
    end

    test "every kommune has a unique four-digit code and a name" do
      codes = @index.codes
      assert_equal codes.size, codes.uniq.size, "duplicate kommune codes"
      codes.each { |c| assert_match(/\A\d{4}\z/, c) }
      @index.kommuner.each { |k| assert k.navn.present?, "#{k.kode} has no name" }
    end

    test "adjacency is symmetric and never self-referential" do
      @index.codes.each do |kode|
        @index.neighbours(kode).each do |neighbour|
          refute_equal kode, neighbour, "#{kode} lists itself as a neighbour"
          assert_includes @index.neighbours(neighbour), kode,
                          "#{kode} lists #{neighbour} but not vice versa"
        end
      end
    end

    test "adjacency identifies Frederiksberg as an enclave of Copenhagen" do
      # Frederiksberg is entirely surrounded by Kobenhavn, so it must have
      # exactly one neighbour. A broken adjacency build tends to show up here
      # first, either as zero neighbours or as the whole capital region.
      assert_equal [ "0101" ], @index.neighbours("0147")
      assert_includes @index.neighbours("0101"), "0147"
    end

    test "island kommuner have no land neighbours" do
      %w[0400 0741 0825 0492 0563].each do |island|
        assert_empty @index.neighbours(island),
                     "#{island} #{@index.find(island).navn} should have no land border"
      end
    end

    test "lookup is fast enough to run on every location update" do
      # 500 lookups should be well under a second; if this regresses we have
      # lost the bbox prefilter.
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      500.times { @index.lookup(lat: 56.1629, lon: 10.2039) }
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      assert_operator elapsed, :<, 1.0, "500 lookups took #{elapsed.round(3)}s"
    end
  end
end
