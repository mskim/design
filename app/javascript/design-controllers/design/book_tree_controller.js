import { Controller } from "@hotwired/stimulus"
import { parseOpen, toggled, cookieFor, gridState } from "design-controllers/design/book_tree"

// The sidebar's book tree: opening/closing a matter group (<details data-matter>)
// remembers the open groups in a cookie (so the server renders the next page the
// same way) and shows/hides the matching theme-page grid sections at once.
// A group pinned open because it holds the current design (data-pinned-open) is
// not saved as open until the user closes and reopens it.
export default class extends Controller {
  static values = { open: String }

  connect() {
    this.keys = parseOpen(this.openValue)
    this.reapply = () => this.apply()
    document.addEventListener("turbo:frame-load", this.reapply)
  }

  disconnect() {
    document.removeEventListener("turbo:frame-load", this.reapply)
  }

  toggle(event) {
    const details = event.currentTarget
    if ("pinnedOpen" in details.dataset) {
      if (details.open) return // the parse-time toggle of a pinned group
      delete details.dataset.pinnedOpen
    }
    const next = toggled(this.keys, details.dataset.matter, details.open)
    if (next === this.keys) return
    this.keys = next
    document.cookie = cookieFor(next)
    this.apply()
  }

  apply() {
    const sections = [...document.querySelectorAll("[data-doc-grid] section[data-matter]")]
    const { hidden, hintHidden } = gridState(this.keys, sections.map((s) => s.dataset.matter))
    sections.forEach((section, i) => { section.hidden = hidden[i] })
    const hint = document.querySelector("[data-doc-grid-empty]")
    if (hint) hint.hidden = hintHidden
  }
}
