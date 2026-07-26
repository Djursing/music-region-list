# frozen_string_literal: true

module Trips
  # Deals a pool of artists across Denmark's kommuner.
  #
  # Two things matter beyond randomness:
  #
  # 1. Balance. With 12 artists and 98 kommuner nobody should end up owning 30
  #    zones while someone else owns two, so each artist is given a capacity of
  #    either floor(98/n) or ceil(98/n) and the assignment never exceeds it.
  #
  # 2. Neighbours. Crossing a border should change the music. Handing the same
  #    artist to two adjacent kommuner makes a crossing silent, so the assigner
  #    avoids it where the pool allows.
  #
  # This is graph colouring with capacities, which is NP-hard in general, so the
  # approach is the standard greedy heuristic: colour the most constrained zones
  # first and prefer the artist with the most headroom left. It is not optimal,
  # but on the real Danish adjacency graph it reaches zero collisions with any
  # pool of about ten artists or more — see the tests, which assert on measured
  # collision rates rather than on a fixed arrangement.
  #
  # Works on plain IDs rather than records so it can be exercised without the
  # database and reasoned about on its own.
  class ZoneAssigner
    class NoArtistsAvailable < StandardError; end

    # Smallest pool that reliably colours the whole map without a silent border.
    #
    # Kommune borders form a planar graph, so the Four Colour Theorem puts the
    # theoretical floor at 4; balancing zone counts across artists costs a
    # little of that freedom and measurement puts the practical floor at 6.
    # Below this, some crossings will not change the music. Pinned by
    # test/models/trips/zone_assigner_test.rb.
    MINIMUM_POOL_FOR_CLEAN_MAP = 6

    Result = Struct.new(:assignments, :neighbour_collisions, keyword_init: true) do
      # kommune_kode => artist_id
      def collision_free? = neighbour_collisions.zero?
    end

    def initialize(artist_ids:, kommune_codes:, adjacency:, random: Random.new)
      raise NoArtistsAvailable, "Need at least one artist to fill the map" if artist_ids.empty?

      @artist_ids = artist_ids
      @kommune_codes = kommune_codes
      @adjacency = adjacency
      @random = random
    end

    def call
      capacities = build_capacities
      assignments = {}
      collisions = 0

      ordered_codes.each do |kode|
        taken = neighbour_artists(kode, assignments)

        artist_id = pick(capacities, avoiding: taken)
        if artist_id.nil?
          # Every artist with headroom already borders this kommune. Unavoidable
          # once the pool is smaller than the local degree, so take the best
          # available and record it rather than leaving the zone empty.
          artist_id = pick(capacities, avoiding: [])
          collisions += 1
        end

        capacities[artist_id] -= 1
        assignments[kode] = artist_id
      end

      Result.new(assignments: assignments, neighbour_collisions: collisions)
    end

    private

    attr_reader :artist_ids, :kommune_codes, :adjacency, :random

    def build_capacities
      shuffled = artist_ids.shuffle(random: random)
      base, extra = kommune_codes.size.divmod(shuffled.size)

      # The remainder is spread over the first few of an already shuffled list,
      # so which artists get the extra zone is itself random.
      shuffled.each_with_index.to_h { |id, i| [ id, base + (i < extra ? 1 : 0) ] }
    end

    # Most constrained first: a kommune bordering nine others is far harder to
    # place late than an island bordering none, so it gets first choice.
    # Shuffled before sorting so equal-degree zones vary between trips.
    def ordered_codes
      kommune_codes.shuffle(random: random).sort_by { |kode| -adjacency.fetch(kode, []).size }
    end

    def neighbour_artists(kode, assignments)
      adjacency.fetch(kode, []).filter_map { |neighbour| assignments[neighbour] }
    end

    # Prefers the artist with the most unused capacity, which keeps the
    # distribution even and leaves the most freedom for later zones.
    def pick(capacities, avoiding:)
      candidates = capacities.reject { |id, remaining| remaining.zero? || avoiding.include?(id) }
      return nil if candidates.empty?

      best = candidates.values.max
      candidates.select { |_, remaining| remaining == best }.keys.sample(random: random)
    end
  end
end
