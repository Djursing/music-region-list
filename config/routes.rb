Rails.application.routes.draw do
  root "home#show"

  # Spotify requires an exact redirect URI match, and no longer accepts
  # "localhost" — register http://127.0.0.1:3000/auth/spotify/callback for
  # development alongside the production URL.
  get  "auth/spotify",          to: "spotify_auth#create",   as: :spotify_auth
  get  "auth/spotify/callback", to: "spotify_auth#callback", as: :spotify_auth_callback
  delete "auth/spotify",        to: "spotify_auth#destroy",  as: :spotify_sign_out

  resources :playlists, only: %i[index show create destroy] do
    resources :artists, only: :update, controller: "playlist_artists"
    resources :trips, only: :create, shallow: true
  end

  get "geo/kommuner.geojson", to: "geo#kommuner", as: :kommuner_boundaries, defaults: { format: "json" }

  resources :trips, only: %i[index show update destroy] do
    # Zones are addressed by kommune code ("0101"), not by record id, since
    # that is what the map hands back when a region is clicked.
    resources :zones, only: %i[show update], controller: "trips/zones", constraints: { id: /\d{4}/ }
  end

  # Development-only. Never drawn in any other environment, and DevController
  # re-checks the environment on every action.
  if Rails.env.development?
    get "dev/sign_in/:spotify_user_id", to: "dev#sign_in_as", as: :dev_sign_in
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
