# music-region-list

A roadtrip soundtrack that follows the map. Denmark is divided into its 98
kommuner, each kommune is randomly assigned a music artist, and as you drive the
app queues a track by whichever artist owns the region you're currently in — so
the music changes when you cross a municipal border.

The app never plays audio itself. Spotify on your phone stays the player (over
the car's Bluetooth); this is only a remote control that pushes tracks into its
queue.

## How it works

- You paste a Spotify playlist link. Every distinct artist in it becomes the
  artist pool.
- Creating a trip shuffles that pool across all 98 kommuner, re-using artists
  when the pool is smaller than 98 and avoiding giving the same artist to two
  neighbouring kommuner where possible.
- While driving, the browser posts your position; the server resolves it to a
  kommune and queues a track by that kommune's artist roughly 25 seconds before
  the current song ends.
- A zone plays its artist's songs *from your playlist* first, and only widens to
  the artist's wider catalogue once those run out.

## Requirements

- Ruby 3.4, Node 22+, Docker (for the local Postgres)
- A Spotify **Premium** account — the playback queue API does not work without it
- A Spotify developer app. Since February 2026, Development Mode apps require the
  app owner to hold active Premium and allow at most **5 test users**, each of
  which must be added by hand in the developer dashboard.

## Setup

```bash
bundle install
yarn install
bin/rails db:prepare
bin/rails test
bin/dev                # starts Postgres, web, jobs and asset watchers
```

`bin/dev` takes no arguments — it brings up the whole stack, including the
Postgres container. `bin/dev-db` manages that container on its own and takes
`up`, `down`, `psql` or `destroy`.

Then open **http://127.0.0.1:3000** — not `localhost:3000`. Spotify matches
redirect URIs exactly, and no longer accepts `localhost` at all.

### Spotify credentials

Create an app at [developer.spotify.com](https://developer.spotify.com/dashboard)
with the redirect URI `http://127.0.0.1:3000/auth/spotify/callback` and the Web
API enabled (not the Web Playback SDK — this app never plays audio itself). Then:

```bash
# Avoids putting the secret in shell history or scrollback.
read -rs -p "Client secret: " S && echo && \
  SPOTIFY_CLIENT_ID=<your id> SPOTIFY_CLIENT_SECRET="$S" bin/rails spotify:configure && unset S

bin/rails spotify:verify   # confirms the pair works
```

Finally add yourself under **User Management** in the Spotify dashboard. In
Development Mode only listed users can authenticate — including the app owner —
and there are five slots.

## Geographic data

Kommune boundaries come from [DAWA / Dataforsyningen](https://dawadocs.dataforsyningen.dk/),
the official Danish administrative geography. They are committed to the repo
rather than fetched at runtime.

```bash
bin/rails geo:kommuner    # refetch (~119 MB) and re-simplify -> lib/geo/kommuner.geojson
bin/rails geo:adjacency   # recompute which kommuner share a land border
bin/rails geo:verify      # check lookups against DAWA's reverse-geocoder
```

The committed file is simplified to 3% of the source vertices — measured at
99.90% point-in-polygon agreement with the full-resolution data over 3,000
random points, where every disagreement is between *adjacent* kommuner. See the
comments in `lib/tasks/geo.rake` for the tradeoff.

Two quirks of the source data are handled explicitly:

- It contains **99** features, not 98. The extra one is Christiansø, a fortress
  island administered directly by the Ministry of Defence that belongs to no
  kommune, and it is filtered out.
- **66 of 98** kommuner are genuine MultiPolygons (Tårnby alone has 157 pieces)
  and 7 contain holes, so containment tests must handle both.

## A limitation worth knowing

You can lock the phone and the music will keep queueing — that loop runs on the
server. But **your location cannot be read while the phone is locked or the tab
is backgrounded**: iOS offers no background geolocation to web apps, in Safari or
in installed PWAs. When that happens the server dead-reckons from your last fix
using its speed and heading, so playback continues from an increasingly stale
position rather than stopping. Best results come from keeping the app in the
foreground on a dashboard mount, where a screen wake lock holds it awake.
