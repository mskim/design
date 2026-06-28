import { Controller } from "@hotwired/stimulus"

// The preview's clickable zones are SVG <a> elements. Turbo's global link handler
// chokes on an SVG anchor's href (an SVGAnimatedString, not a String) — it throws
// "t.href.startsWith is not a function" on every click. So the overlay zones carry
// no href; this controller navigates on click via a clean Turbo Drive visit.
export default class extends Controller {
  static values = { url: String }

  navigate(event) {
    event.preventDefault()
    if (!this.urlValue) return
    if (window.Turbo) {
      window.Turbo.visit(this.urlValue)
    } else {
      window.location.assign(this.urlValue)
    }
  }
}
