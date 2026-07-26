# frozen_string_literal: true

module Trips
  # Works out where the car is now, which is harder than reading the last fix.
  #
  # The phone can only report its position while the browser is in the
  # foreground. iOS gives web apps no background geolocation at all — not in
  # Safari, not in an installed PWA — so the moment the screen locks or the
  # driver switches to a maps app, updates stop arriving while the music keeps
  # playing.
  #
  # Rather than freeze on the last known kommune, the resolver projects forward
  # from the last fix using the speed and heading the Geolocation API supplied
  # with it. On a motorway at steady speed that stays close for a useful while.
  # It is still a guess, so it is labelled as one and abandoned entirely once it
  # gets old enough to be fiction.
  class PositionResolver
    EARTH_RADIUS_METRES = 6_371_000.0

    # A fix younger than this is used as-is; no point extrapolating over a
    # couple of seconds of latency.
    FRESH_WINDOW = 30.seconds

    # Past this, dead reckoning is abandoned. Ten minutes at motorway speed is
    # roughly 18 km — far enough to be several kommuner wrong, and by then the
    # honest answer is "unknown" rather than a confident wrong one.
    MAX_EXTRAPOLATION = 10.minutes

    # Below walking pace the heading reported by a phone is mostly noise, so
    # projecting along it would invent movement that isn't happening.
    MIN_SPEED_FOR_PROJECTION = 1.5 # metres/second, ~5 km/h

    Position = Struct.new(:latitude, :longitude, :kommune, :source, :fix_age, keyword_init: true) do
      # :fix       — a real reading from the phone
      # :estimated — projected forward from the last fix
      # :stale     — too old to project from; position unknown
      def live? = source == :fix
      def estimated? = source == :estimated
      def unknown? = kommune.nil?
    end

    def initialize(trip, now: Time.current)
      @trip = trip
      @now = now
    end

    def call
      last = @trip.trip_locations.most_recent.first
      return nil if last.nil?

      age = @now - last.recorded_at

      if age <= FRESH_WINDOW
        build(last.latitude.to_f, last.longitude.to_f, :fix, age)
      elsif age <= MAX_EXTRAPOLATION && projectable?(last)
        latitude, longitude = project(last, age)
        build(latitude, longitude, :estimated, age)
      else
        # Hold the last known coordinates so the UI can still say where we were,
        # but mark it stale so nothing treats it as current.
        build(last.latitude.to_f, last.longitude.to_f, :stale, age)
      end
    end

    private

    def projectable?(location)
      location.speed.present? &&
        location.speed >= MIN_SPEED_FOR_PROJECTION &&
        location.heading.present?
    end

    # Great-circle projection from a point along a bearing. Straight-line, so it
    # ignores that roads bend — acceptable over a few minutes of motorway, and
    # the reason MAX_EXTRAPOLATION exists.
    def project(location, age)
      distance = location.speed * age
      angular = distance / EARTH_RADIUS_METRES

      lat1 = to_radians(location.latitude.to_f)
      lon1 = to_radians(location.longitude.to_f)
      bearing = to_radians(location.heading.to_f)

      lat2 = Math.asin(
        (Math.sin(lat1) * Math.cos(angular)) +
        (Math.cos(lat1) * Math.sin(angular) * Math.cos(bearing))
      )
      lon2 = lon1 + Math.atan2(
        Math.sin(bearing) * Math.sin(angular) * Math.cos(lat1),
        Math.cos(angular) - (Math.sin(lat1) * Math.sin(lat2))
      )

      [ to_degrees(lat2), normalise_longitude(to_degrees(lon2)) ]
    end

    def build(latitude, longitude, source, age)
      kommune = Geo::KommuneIndex.instance.lookup(lat: latitude, lon: longitude) unless source == :stale

      Position.new(
        latitude: latitude,
        longitude: longitude,
        kommune: kommune,
        source: source,
        fix_age: age
      )
    end

    def to_radians(degrees) = degrees * Math::PI / 180
    def to_degrees(radians) = radians * 180 / Math::PI
    def normalise_longitude(degrees) = ((degrees + 540) % 360) - 180
  end
end
