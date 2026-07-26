import { Controller } from "@hotwired/stimulus"

// Bridges a server-rendered zone swap back to the map.
//
// Turbo can replace the panel's markup but cannot repaint a WebGL canvas, so
// the update response appends this element; on connect it announces the change
// and removes itself. Doing it through an element rather than an inline script
// keeps the page compatible with a strict Content-Security-Policy.
export default class extends Controller {
  static values = { kode: String, artist: String, artistId: Number, color: String }

  connect() {
    window.dispatchEvent(
      new CustomEvent("zone:updated", {
        detail: {
          kode: this.kodeValue,
          artist: this.artistValue,
          artistId: this.artistIdValue,
          color: this.colorValue,
        },
      })
    )

    this.element.remove()
  }
}
