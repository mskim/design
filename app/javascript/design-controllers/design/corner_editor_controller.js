import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "box", "tl", "tr", "br", "bl"]

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
  }

  parts() {
    const val = this.inputTarget.value || "0,0,0,0"
    return val.split(",").map(s => s.trim())
  }

  updateVisual() {
    const p = this.parts()
    const corners = ["tl", "tr", "br", "bl"]
    const radius = []
    corners.forEach((c, i) => {
      const el = this[`${c}Target`]
      if (p[i] === "1") {
        el.style.background = "#f59e0b"
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
