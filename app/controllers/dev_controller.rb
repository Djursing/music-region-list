# frozen_string_literal: true

# Development-only helpers for exercising the app without a live Spotify
# connection.
#
# The routes for this controller are only drawn when Rails.env.development?
# (see config/routes.rb), and every action re-checks the environment here too —
# an authentication bypass is worth defending twice.
class DevController < ApplicationController
  allow_unauthenticated
  before_action :ensure_development!

  # These are driven from a terminal, not a browser form, so there is no token
  # to send. Safe only because the routes are not drawn outside development.
  skip_forgery_protection

  # Signs in as an existing account so pages behind auth can be opened while
  # working on them. Real sign-in always goes through Spotify.
  def sign_in_as
    account = SpotifyAccount.find_by!(spotify_user_id: params[:spotify_user_id])
    sign_in(account)
    redirect_to params[:return_to].presence || trips_path
  end

  # Walks a trip along a route, feeding the same endpoint the phone uses.
  #
  # The alternative to this is debugging the driving loop on a motorway, which
  # is both slow and a bad idea. A whole Copenhagen-to-Aarhus drive resolves in
  # under a second here, exercising every border crossing on the way.
  ROUTES = {
    "kbh-aarhus" => [
      [ 55.6761, 12.5683 ],  # Radhuspladsen
      [ 55.6580, 12.3600 ],  # Glostrup / Hoje-Taastrup
      [ 55.6415, 12.0803 ],  # Roskilde
      [ 55.4600, 11.7900 ],  # Ringsted
      [ 55.3900, 11.3500 ],  # Slagelse
      [ 55.3400, 11.1300 ],  # Korsor
      [ 55.3128, 10.7893 ],  # Nyborg
      [ 55.4038, 10.4024 ],  # Odense
      [ 55.5200, 9.7500 ],   # Middelfart
      [ 55.7100, 9.5400 ],   # Vejle
      [ 55.8600, 9.8400 ],   # Horsens
      [ 56.0300, 10.0300 ],  # Skanderborg
      [ 56.1629, 10.2039 ]   # Aarhus
    ].freeze
  }.freeze

  def simulate_drive
    trip = SpotifyAccount.find(session[:spotify_account_id]).trips.find(params[:trip_id])
    waypoints = ROUTES.fetch(params[:route] || "kbh-aarhus")
    steps_per_leg = (params[:steps_per_leg] || 8).to_i
    speed = (params[:speed] || 30.0).to_f # metres/second, ~108 km/h

    visited = []
    previous_kode = nil

    interpolate(waypoints, steps_per_leg).each do |(lat, lon), heading|
      trip.trip_locations.create!(
        latitude: lat, longitude: lon, speed: speed, heading: heading,
        accuracy: 8.0, recorded_at: Time.current
      )

      kommune = Geo::KommuneIndex.instance.lookup(lat: lat, lon: lon)
      next if kommune.nil? || kommune.kode == previous_kode

      previous_kode = kommune.kode
      visited << { kode: kommune.kode, kommune: kommune.navn, artist: trip.artist_for(kommune.kode)&.name }
    end

    trip.update!(current_kommune_kode: previous_kode) if previous_kode
    trip.broadcast_hud

    render json: { points: interpolate(waypoints, steps_per_leg).size, crossings: visited }
  end

  private

  # Straight-line interpolation between waypoints, with the bearing to the next
  # point so dead reckoning has a heading to work from.
  def interpolate(waypoints, steps_per_leg)
    waypoints.each_cons(2).flat_map do |(lat1, lon1), (lat2, lon2)|
      bearing = bearing_between(lat1, lon1, lat2, lon2)
      (0...steps_per_leg).map do |step|
        fraction = step.to_f / steps_per_leg
        [ [ lat1 + ((lat2 - lat1) * fraction), lon1 + ((lon2 - lon1) * fraction) ], bearing ]
      end
    end
  end

  def bearing_between(lat1, lon1, lat2, lon2)
    to_rad = ->(d) { d * Math::PI / 180 }
    dlon = to_rad.call(lon2 - lon1)
    y = Math.sin(dlon) * Math.cos(to_rad.call(lat2))
    x = (Math.cos(to_rad.call(lat1)) * Math.sin(to_rad.call(lat2))) -
        (Math.sin(to_rad.call(lat1)) * Math.cos(to_rad.call(lat2)) * Math.cos(dlon))
    ((Math.atan2(y, x) * 180 / Math::PI) + 360) % 360
  end

  def ensure_development!
    raise ActionController::RoutingError, "Not available" unless Rails.env.development?
  end
end
