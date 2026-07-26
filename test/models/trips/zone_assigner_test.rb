# frozen_string_literal: true

require "test_helper"

module Trips
  class ZoneAssignerTest < ActiveSupport::TestCase
    # The real Danish adjacency graph — 98 kommuner, 186 borders, max degree 9.
    # Using it rather than a toy graph means the collision assertions below say
    # something about the actual product.
    def real_graph
      index = Geo::KommuneIndex.instance
      [ index.codes, index.codes.index_with { |kode| index.neighbours(kode) } ]
    end

    def assign(artist_count, seed: 1234)
      codes, adjacency = real_graph
      ZoneAssigner.new(
        artist_ids: (1..artist_count).to_a,
        kommune_codes: codes,
        adjacency: adjacency,
        random: Random.new(seed)
      ).call
    end

    test "every kommune receives exactly one artist" do
      result = assign(12)

      assert_equal 98, result.assignments.size
      assert_equal Geo::KommuneIndex.instance.codes.sort, result.assignments.keys.sort
      assert result.assignments.values.all? { |id| (1..12).cover?(id) }
    end

    test "zones are shared out evenly rather than clumping" do
      result = assign(12)
      counts = result.assignments.values.tally.values

      # 98 across 12 artists is 8 remainder 2, so everyone gets 8 or 9.
      assert_equal 9, counts.max
      assert_equal 8, counts.min
      assert_equal 98, counts.sum
    end

    test "a modest pool avoids silent borders entirely" do
      [ 6, 12, 25, 60 ].each do |count|
        result = assign(count)
        assert result.collision_free?,
               "#{count} artists still produced #{result.neighbour_collisions} silent borders"
      end
    end

    test "a pool larger than the map gives every zone a different artist" do
      result = assign(150)

      assert_equal 98, result.assignments.values.uniq.size
      assert result.collision_free?
    end

    test "degrades gracefully when the pool is too small to avoid collisions" do
      # With fewer artists than a kommune has neighbours, some borders must be
      # silent. The assignment must still be complete and balanced.
      result = assign(3)

      assert_equal 98, result.assignments.size
      assert_operator result.neighbour_collisions, :>, 0
      counts = result.assignments.values.tally.values
      assert_operator counts.max - counts.min, :<=, 1, "must stay balanced even when colliding"
    end

    test "a single artist fills the whole map" do
      result = assign(1)

      assert_equal 98, result.assignments.size
      assert_equal [ 1 ], result.assignments.values.uniq
    end

    test "refuses to assign with an empty pool" do
      codes, adjacency = real_graph
      assert_raises(ZoneAssigner::NoArtistsAvailable) do
        ZoneAssigner.new(artist_ids: [], kommune_codes: codes, adjacency: adjacency)
      end
    end

    test "the same seed reproduces the same map and different seeds do not" do
      assert_equal assign(12, seed: 7).assignments, assign(12, seed: 7).assignments
      refute_equal assign(12, seed: 7).assignments, assign(12, seed: 8).assignments
    end

    test "collision counts hold across many random seeds" do
      # A single lucky seed proves nothing about a greedy heuristic, so check
      # the property holds broadly.
      collisions = (1..25).map { |seed| assign(12, seed: seed).neighbour_collisions }

      assert_equal [ 0 ], collisions.uniq,
                   "expected no silent borders with 12 artists, saw #{collisions.tally}"
    end

    test "documents the smallest pool that reliably colours the whole map" do
      # Kommune borders form a planar graph, so the Four Colour Theorem puts the
      # theoretical floor at 4. Balancing zone counts across artists costs a
      # little of that freedom, and measurement puts the practical floor at 6.
      #
      # This is the number the UI warns against dropping below, so it is pinned
      # here: if the adjacency data ever changes, this test says so.
      worst = ->(count) { (1..40).map { |s| assign(count, seed: s).neighbour_collisions }.max }

      assert_operator worst.call(4), :>, 0, "4 artists should not reliably suffice"
      assert_operator worst.call(5), :>, 0, "5 artists should not reliably suffice"
      assert_equal 0, worst.call(6), "6 artists should always suffice"
    end
  end
end
