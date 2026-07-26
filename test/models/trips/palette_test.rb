# frozen_string_literal: true

require "test_helper"

module Trips
  class PaletteTest < ActiveSupport::TestCase
    test "produces a valid hex colour per artist" do
      colors = Palette.for([ 5, 9, 2 ])

      assert_equal [ 5, 9, 2 ], colors.keys
      colors.each_value { |hex| assert_match(/\A#[0-9a-f]{6}\z/, hex) }
    end

    test "colours are distinct across a realistic pool" do
      colors = Palette.for((1..30).to_a).values
      assert_equal 30, colors.uniq.size
    end

    test "adjacent artists are not near-identical hues" do
      # Golden-angle spacing exists precisely so consecutive entries land far
      # apart on the colour wheel; even spacing would make neighbours in a
      # 30-artist pool nearly indistinguishable.
      first, second = Palette.for([ 1, 2 ]).values
      assert_operator channel_distance(first, second), :>, 60
    end

    test "an artist's colour depends only on its position, so it is stable" do
      assert_equal Palette.for([ 7, 8, 9 ]), Palette.for([ 7, 8, 9 ])
    end

    test "handles a single artist and an empty pool" do
      assert_equal 1, Palette.for([ 42 ]).size
      assert_empty Palette.for([])
    end

    private

    def channel_distance(a, b)
      rgb = ->(hex) { hex.delete("#").scan(/../).map { |c| c.to_i(16) } }
      rgb.call(a).zip(rgb.call(b)).sum { |x, y| (x - y).abs }
    end
  end
end
