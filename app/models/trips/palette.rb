# frozen_string_literal: true

module Trips
  # Assigns each artist on a trip a distinct colour for the map and legend.
  #
  # Hues are spaced by the golden angle rather than divided evenly, so the
  # colours stay well separated whether a trip has five artists or fifty, and
  # adding one artist doesn't reshuffle every other hue.
  #
  # Colour is derived from the artist's position in a stable ordering, so an
  # artist re-used across several kommuner is the same colour everywhere on the
  # map — the repetition reads as deliberate rather than as a rendering bug.
  class Palette
    GOLDEN_ANGLE = 137.508

    # Mid-range saturation and lightness so fills stay legible against a dark
    # basemap without vibrating next to each other.
    SATURATION = 0.62
    LIGHTNESS = 0.58

    def self.for(artist_ids)
      artist_ids.each_with_index.to_h do |artist_id, index|
        [ artist_id, hsl_to_hex((index * GOLDEN_ANGLE) % 360, SATURATION, LIGHTNESS) ]
      end
    end

    def self.hsl_to_hex(hue, saturation, lightness)
      chroma = (1 - ((2 * lightness) - 1).abs) * saturation
      secondary = chroma * (1 - (((hue / 60.0) % 2) - 1).abs)
      match = lightness - (chroma / 2)

      red, green, blue =
        case hue
        when 0...60    then [ chroma, secondary, 0 ]
        when 60...120  then [ secondary, chroma, 0 ]
        when 120...180 then [ 0, chroma, secondary ]
        when 180...240 then [ 0, secondary, chroma ]
        when 240...300 then [ secondary, 0, chroma ]
        else                [ chroma, 0, secondary ]
        end

      format("#%02x%02x%02x",
             ((red + match) * 255).round,
             ((green + match) * 255).round,
             ((blue + match) * 255).round)
    end
  end
end
