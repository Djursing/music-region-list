import { Controller } from "@hotwired/stimulus"

// Reports the car's position while the driving screen is open, and fights to
// keep the screen awake so it stays open.
//
// This is the honest limit of the whole app: iOS gives web apps no background
// geolocation, in Safari or in an installed PWA. Once the screen locks or the
// driver switches apps, positions stop arriving. The music keeps playing —
// that loop runs on the server — but the server has to estimate where the car
// is. Hence the wake lock, and hence being explicit in the UI about which of
// the two situations you are in.
export default class extends Controller {
  static values = {
    url: String,
    interval: { type: Number, default: 10000 },
  }

  static targets = ["gps", "wakeLock"]

  connect() {
    this.#startWatching()
    this.#requestWakeLock()

    // A wake lock is released automatically whenever the page is hidden, and is
    // NOT restored when it comes back. In a car you will glance at a maps app
    // and return, so without this the screen quietly starts sleeping again.
    this.boundVisibility = this.#onVisibilityChange.bind(this)
    document.addEventListener("visibilitychange", this.boundVisibility)
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.boundVisibility)
    if (this.watchId != null) navigator.geolocation.clearWatch(this.watchId)
    this.#releaseWakeLock()
  }

  // --- Position -----------------------------------------------------------

  #startWatching() {
    if (!("geolocation" in navigator)) {
      this.#setGps("This browser cannot report location", "bad")
      return
    }

    this.watchId = navigator.geolocation.watchPosition(
      (position) => this.#onPosition(position),
      (error) => this.#onPositionError(error),
      { enableHighAccuracy: true, maximumAge: 5000, timeout: 20000 }
    )
  }

  #onPosition(position) {
    this.lastFixAt = Date.now()
    this.#setGps("Live GPS", "good")

    // watchPosition can fire far more often than we want to write rows, so
    // updates are throttled to roughly the reporting interval.
    if (this.lastSentAt && Date.now() - this.lastSentAt < this.intervalValue) return
    this.lastSentAt = Date.now()

    const { latitude, longitude, speed, heading, accuracy } = position.coords

    fetch(this.urlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content ?? "",
      },
      body: JSON.stringify({ location: { latitude, longitude, speed, heading, accuracy } }),
    }).catch(() => {
      // Rural Denmark has holes in coverage. A dropped update is not worth
      // interrupting the driver over — the next one will carry the position.
      this.#setGps("No signal — will retry", "warn")
    })
  }

  #onPositionError(error) {
    const message =
      error.code === error.PERMISSION_DENIED
        ? "Location permission denied"
        : "Cannot get a location fix"
    this.#setGps(message, "bad")
  }

  // --- Wake lock ----------------------------------------------------------

  async #requestWakeLock() {
    if (!("wakeLock" in navigator)) {
      this.#setWakeLock("Screen may sleep — this browser has no wake lock")
      return
    }

    try {
      this.wakeLock = await navigator.wakeLock.request("screen")
      this.#setWakeLock("Screen kept awake")
      this.wakeLock.addEventListener("release", () => this.#setWakeLock("Screen lock released"))
    } catch {
      this.#setWakeLock("Could not keep the screen awake")
    }
  }

  #releaseWakeLock() {
    this.wakeLock?.release?.().catch(() => {})
    this.wakeLock = null
  }

  #onVisibilityChange() {
    if (document.visibilityState === "visible") this.#requestWakeLock()
  }

  // --- Status -------------------------------------------------------------

  #setGps(message, level) {
    if (!this.hasGpsTarget) return
    this.gpsTarget.textContent = message
    this.gpsTarget.dataset.level = level
  }

  #setWakeLock(message) {
    if (this.hasWakeLockTarget) this.wakeLockTarget.textContent = message
  }
}
