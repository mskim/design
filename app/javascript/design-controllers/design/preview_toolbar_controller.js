import { Controller } from "@hotwired/stimulus"
import { printCookie, GUIDES_KEY } from "design-controllers/design/page_guides"

// The preview section's toggles; they sit outside #preview_frame, so every
// frame replacement keeps them.
// • 안내선: data-guides="on|off" on this element (the pages' guide layers hide
//   under "off"), remembered per browser in localStorage — guarded, storage
//   can throw (private mode, blocked site data).
// • 인쇄용: the design_preview_print cookie that every preview request reads;
//   toggling it reloads the frame. Rendered disabled for doc types the engine
//   never binds.
export default class extends Controller {
  static targets = ["guides", "print"]
  static values = { previewUrl: String }

  connect() { this.showGuides(readGuides()) }

  toggleGuides() {
    const on = this.element.dataset.guides !== "on"
    this.showGuides(on)
    try { window.localStorage.setItem(GUIDES_KEY, on ? "on" : "off") } catch {}
  }

  togglePrint() {
    if (!this.hasPrintTarget || this.printTarget.disabled) return
    const on = this.printTarget.getAttribute("aria-pressed") !== "true"
    document.cookie = printCookie(on)
    this.printTarget.setAttribute("aria-pressed", String(on))
    this.reloadPreview()
  }

  showGuides(on) {
    this.element.dataset.guides = on ? "on" : "off"
    if (this.hasGuidesTarget) this.guidesTarget.setAttribute("aria-pressed", String(on))
  }

  // A stream-replaced frame has no src: set it; an unchanged src reloads.
  reloadPreview() {
    const frame = this.element.querySelector("turbo-frame#preview_frame")
    if (!frame || !this.previewUrlValue) return
    if (frame.getAttribute("src") === this.previewUrlValue) frame.reload()
    else frame.setAttribute("src", this.previewUrlValue)
  }
}

function readGuides() {
  try { return window.localStorage.getItem(GUIDES_KEY) !== "off" } catch { return true }
}
