import { Controller } from "@hotwired/stimulus"
import { GUIDES_KEY } from "design-controllers/design/page_guides"

// The preview section's 안내선 toggle; it sits outside #preview_frame, so every
// frame replacement keeps it. data-guides="on|off" on this element (the pages'
// guide layers hide under "off"), remembered per browser in localStorage —
// guarded, storage can throw (private mode, blocked site data). The preview is
// always in print mode (server side), so there is no 인쇄용 toggle.
export default class extends Controller {
  static targets = ["guides"]

  connect() { this.showGuides(readGuides()) }

  toggleGuides() {
    const on = this.element.dataset.guides !== "on"
    this.showGuides(on)
    try { window.localStorage.setItem(GUIDES_KEY, on ? "on" : "off") } catch {}
  }

  showGuides(on) {
    this.element.dataset.guides = on ? "on" : "off"
    if (this.hasGuidesTarget) this.guidesTarget.setAttribute("aria-pressed", String(on))
  }
}

function readGuides() {
  try { return window.localStorage.getItem(GUIDES_KEY) !== "off" } catch { return true }
}
