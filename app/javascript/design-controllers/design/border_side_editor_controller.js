import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "box"]
  static values = { parent: String }

  connect() {
    this.updateVisual()
  }

  toggle(event) {
    const side = event.currentTarget.dataset.side
    const parts = this.parts()
    const index = { top: 0, right: 1, bottom: 2, left: 3 }[side]
    parts[index] = parts[index] === "1" ? "0" : "1"
    this.inputTarget.value = parts.join(",")
    this.updateVisual()
    // The style panel's autosave listens for change on its form (hidden inputs
    // emit none by themselves).
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  // An inherited (empty) value shows — and starts toggling from — the parent's sides.
  parts() {
    const val = this.inputTarget.value || this.parentValue || "0,0,0,0"
    return val.split(",").map(s => s.trim())
  }

  get inherited() { return this.inputTarget.value === "" && this.parentValue !== "" }

  parentValueChanged() { if (this.hasBoxTarget && this.hasInputTarget) this.updateVisual() }

  updateVisual() {
    const p = this.parts()
    const box = this.boxTarget
    const on = this.inherited ? "#94a3b8" : "#3b82f6"
    box.style.borderTopWidth = p[0] === "1" ? "3px" : "1px"
    box.style.borderTopStyle = p[0] === "1" ? "solid" : "dashed"
    box.style.borderTopColor = p[0] === "1" ? on : "#d1d5db"
    box.style.borderRightWidth = p[1] === "1" ? "3px" : "1px"
    box.style.borderRightStyle = p[1] === "1" ? "solid" : "dashed"
    box.style.borderRightColor = p[1] === "1" ? on : "#d1d5db"
    box.style.borderBottomWidth = p[2] === "1" ? "3px" : "1px"
    box.style.borderBottomStyle = p[2] === "1" ? "solid" : "dashed"
    box.style.borderBottomColor = p[2] === "1" ? on : "#d1d5db"
    box.style.borderLeftWidth = p[3] === "1" ? "3px" : "1px"
    box.style.borderLeftStyle = p[3] === "1" ? "solid" : "dashed"
    box.style.borderLeftColor = p[3] === "1" ? on : "#d1d5db"
  }
}
