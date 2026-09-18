import { Controller } from "@hotwired/stimulus"
import { flagParts, toggleFlag } from "design-controllers/design/edge_flags"

export default class extends Controller {
  static targets = ["input", "box", "tl", "tr", "br", "bl"]
  static values = { parent: String }

  connect() {
    this.updateVisual()
  }

  toggle(event) {
    const corner = event.currentTarget.dataset.corner
    const index = { tl: 0, tr: 1, br: 2, bl: 3 }[corner]
    this.inputTarget.value = toggleFlag(this.inputTarget.value, this.parentValue, index)
    this.updateVisual()
    // The style panel's autosave listens for change on its form (hidden inputs
    // emit none by themselves).
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  // An inherited (empty) value shows — and starts toggling from — the parent's corners.
  parts() { return flagParts(this.inputTarget.value, this.parentValue) }

  get inherited() { return this.inputTarget.value === "" && this.parentValue !== "" }

  parentValueChanged() { if (this.hasBoxTarget && this.hasInputTarget) this.updateVisual() }

  updateVisual() {
    const p = this.parts()
    const set = this.inherited ? "#fcd34d" : "#f59e0b"
    const corners = ["tl", "tr", "br", "bl"]
    const radius = []
    corners.forEach((c, i) => {
      const el = this[`${c}Target`]
      if (p[i] === "1") {
        el.style.background = set
        el.textContent = "\u2713"
        radius.push("8px")
      } else {
        el.style.background = "#d1d5db"
        el.textContent = "\u2717"
        radius.push("0")
      }
    })
    this.boxTarget.style.borderRadius = radius.join(" ")
  }
}
