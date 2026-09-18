import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "box", "tl", "tr", "br", "bl"]
  static values = { parent: String }

  connect() {
    this.updateVisual()
  }

  toggle(event) {
    const corner = event.currentTarget.dataset.corner
    const parts = this.parts()
    const index = { tl: 0, tr: 1, br: 2, bl: 3 }[corner]
    parts[index] = parts[index] === "1" ? "0" : "1"
    this.inputTarget.value = parts.join(",")
    this.updateVisual()
    // The style panel's autosave listens for change on its form (hidden inputs
    // emit none by themselves).
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  // An inherited (empty) value shows — and starts toggling from — the parent's corners.
  parts() {
    const val = this.inputTarget.value || this.parentValue || "0,0,0,0"
    return val.split(",").map(s => s.trim())
  }

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
        el.textContent = "✓"
        radius.push("8px")
      } else {
        el.style.background = "#d1d5db"
        el.textContent = "✗"
        radius.push("0")
      }
    })
    this.boxTarget.style.borderRadius = radius.join(" ")
  }
}
