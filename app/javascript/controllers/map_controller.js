import { Controller } from "@hotwired/stimulus"
// Pinned to maplibre-gl 5. Version 6 exports named symbols instead of a default
// and, more importantly, its initialisation stalls silently under esbuild — the
// map constructs, the style is accepted, but the stylesheet never resolves and
// no error is emitted. Revisit when 6.x has settled.
import maplibregl from "maplibre-gl"

// Renders Denmark's kommuner, coloured by the artist assigned to each.
//
// This is the one part of the app Turbo cannot manage. The map's state lives in
// a WebGL canvas rather than in the DOM, so replacing HTML around it does
// nothing to the rendered zones. Instead the server broadcasts a
// `zone:updated` event after a swap and this controller repaints the affected
// kommune itself.
export default class extends Controller {
  // Denmark's extent, west of Jutland to east of Bornholm. The map is framed by
  // fitting these bounds rather than by a fixed centre and zoom, so the whole
  // country stays visible whether the panel sits beside the map on a desktop or
  // below it on a phone.
  static DENMARK_BOUNDS = [
    [7.8, 54.4],
    [15.4, 57.9],
  ]

  static values = {
    boundariesUrl: String,
    zones: Object,
  }

  static targets = ["canvas", "status"]

  connect() {
    this.map = new maplibregl.Map({
      container: this.canvasTarget,
      style: this.#style(),
      bounds: this.constructor.DENMARK_BOUNDS,
      fitBoundsOptions: { padding: 12 },
      attributionControl: { compact: true },
      // The map is a picker, not a navigation surface — rotating it only makes
      // Denmark harder to recognise at a glance.
      pitchWithRotate: false,
      dragRotate: false,
    })

    this.map.touchZoomRotate.disableRotation()
    this.map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-right")

    this.map.on("load", () => this.#addZoneLayers())
    this.boundZoneUpdated = this.#onZoneUpdated.bind(this)
    window.addEventListener("zone:updated", this.boundZoneUpdated)
  }

  disconnect() {
    window.removeEventListener("zone:updated", this.boundZoneUpdated)
    this.map?.remove()
    this.map = null
  }

  // --- Setup --------------------------------------------------------------

  #style() {
    return {
      version: 8,
      sources: {
        osm: {
          type: "raster",
          tiles: ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
          tileSize: 256,
          attribution: "© OpenStreetMap contributors",
        },
      },
      layers: [
        { id: "background", type: "background", paint: { "background-color": "#0a0a0a" } },
        {
          id: "osm",
          type: "raster",
          source: "osm",
          // Dimmed so the artist colours read as the primary information and
          // the basemap stays context rather than competing with them.
          paint: { "raster-opacity": 0.35, "raster-saturation": -0.7 },
        },
      ],
    }
  }

  #addZoneLayers() {
    this.map.addSource("kommuner", {
      type: "geojson",
      data: this.boundariesUrlValue,
      promoteId: "kode",
    })

    this.map.addLayer({
      id: "kommune-fill",
      type: "fill",
      source: "kommuner",
      paint: {
        "fill-color": this.#colorExpression(),
        "fill-opacity": [
          "case",
          ["boolean", ["feature-state", "selected"], false], 0.92,
          ["boolean", ["feature-state", "hover"], false], 0.8,
          0.62,
        ],
      },
    })

    this.map.addLayer({
      id: "kommune-outline",
      type: "line",
      source: "kommuner",
      paint: {
        "line-color": [
          "case",
          ["boolean", ["feature-state", "selected"], false], "#ffffff",
          "#0a0a0a",
        ],
        "line-width": [
          "case",
          ["boolean", ["feature-state", "selected"], false], 2.5,
          0.5,
        ],
      },
    })

    this.#wireInteractions()
    this.#announce(`${Object.keys(this.zonesValue).length} kommuner loaded`)
  }

  // A `match` expression rather than feature-state for colour: it is one
  // declarative mapping of kommune code to colour, so a repaint is a single
  // setPaintProperty call and there is no per-feature state to keep in sync.
  #colorExpression() {
    const pairs = []
    for (const [kode, zone] of Object.entries(this.zonesValue)) {
      pairs.push(kode, zone.color)
    }

    // `match` needs at least one pair; fall back to a flat grey before a trip
    // has been assigned.
    if (pairs.length === 0) return "#3f3f46"

    return ["match", ["get", "kode"], ...pairs, "#3f3f46"]
  }

  #wireInteractions() {
    this.map.on("mousemove", "kommune-fill", (event) => {
      const kode = event.features?.[0]?.properties?.kode
      if (!kode || kode === this.hoveredKode) return

      this.#setState(this.hoveredKode, { hover: false })
      this.hoveredKode = kode
      this.#setState(kode, { hover: true })
      this.map.getCanvas().style.cursor = "pointer"
    })

    this.map.on("mouseleave", "kommune-fill", () => {
      this.#setState(this.hoveredKode, { hover: false })
      this.hoveredKode = null
      this.map.getCanvas().style.cursor = ""
    })

    this.map.on("click", "kommune-fill", (event) => {
      const kode = event.features?.[0]?.properties?.kode
      if (kode) this.select(kode)
    })
  }

  // --- Selection ----------------------------------------------------------

  select(kode) {
    this.#setState(this.selectedKode, { selected: false })
    this.selectedKode = kode
    this.#setState(kode, { selected: true })

    // Loads the swap panel into the Turbo Frame beside the map. Navigating the
    // frame rather than rendering here keeps every bit of markup on the server.
    const frame = document.getElementById("zone_panel")
    if (frame) frame.src = this.#panelUrl(kode)

    this.#announce(`${this.zonesValue[kode]?.artist ?? "Unknown"} plays in this kommune`)
  }

  #panelUrl(kode) {
    return `${window.location.pathname.replace(/\/$/, "")}/zones/${kode}`
  }

  // --- Reacting to a swap -------------------------------------------------

  #onZoneUpdated(event) {
    const { kode, artist, color, artistId } = event.detail
    if (!kode || !this.map) return

    this.zonesValue = {
      ...this.zonesValue,
      [kode]: { artist, color, artist_id: artistId },
    }

    if (this.map.getLayer("kommune-fill")) {
      this.map.setPaintProperty("kommune-fill", "fill-color", this.#colorExpression())
    }

    this.#announce(`${artist} now plays in this kommune`)
  }

  #setState(kode, state) {
    if (!kode || !this.map?.getSource("kommuner")) return
    this.map.setFeatureState({ source: "kommuner", id: kode }, state)
  }

  // Keeps the change perceivable without sight, since everything else about
  // this interaction is colour on a canvas.
  #announce(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }
}
