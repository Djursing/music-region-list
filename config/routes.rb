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

  resources :trips, only: %i[index show update destroy] do
    # Zones are addressed by kommune code ("0101"), not by record id, since
    # that is what the map hands back when a region is clicked.
    resources :zones, only: :update, controller: "trips/zones", constraints: { id: /\d{4}/ }
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
