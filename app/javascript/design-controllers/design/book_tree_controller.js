import { Controller } from "@hotwired/stimulus"
import { parseOpen, readCookieKeys, toggled, cookieFor, gridState, nextExpanded } from "design-controllers/design/book_tree"

// The sidebar's book tree (book_write's 디자인수정 tree): each section's toggle button
// (aria-expanded) folds the list after its row. Folding a matter section
// (section[data-matter]) remembers the open sections in a cookie (so the server renders
// the next page the same way) and shows/hides the matching theme-page grid sections at
// once; other sections (table styles) just fold. A section pinned open because it holds
// the current design (data-pinned-open) is not saved as open until the user closes and
// reopens it.
export default class extends Controller {
  static values = { open: String }

  // The cookie is the source of truth: on a Turbo restoration visit or cache preview
  // the tree comes from a snapshot whose toggles may be stale.
  connect() {
    this.keys = readCookieKeys(document.cookie) ?? parseOpen(this.openValue)
    this.element.querySelectorAll("section[data-matter]").forEach((section) => {
      const open = this.keys.includes(section.dataset.matter) || "pinnedOpen" in section.dataset
      this.toggleButton(section)?.setAttribute("aria-expanded", String(open))
    })
    this.apply()
    this.reapply = () => this.apply()
    document.addEventListener("turbo:frame-load", this.reapply)
  }

  disconnect() {
    document.removeEventListener("turbo:frame-load", this.reapply)
  }

  toggle(event) {
    const button = event.currentTarget
    const open = nextExpanded(button.getAttribute("aria-expanded"))
    button.setAttribute("aria-expanded", String(open))

    const section = button.closest("section")
    if (!section || !("matter" in section.dataset)) return
    delete section.dataset.pinnedOpen // from here on the section's state is the user's own
    const next = toggled(this.keys, section.dataset.matter, open)
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

  toggleButton(section) {
    return section.querySelector(":scope > .book-tree__row > .book-tree__toggle")
  }
}
