import { Controller } from "@hotwired/stimulus"

// The 3 x 3 anchor proxy (Inputs::AnchorGrid). The hidden input is the value;
// the buttons only show it, so a pick writes the input and dispatches one
// bubbling `change` — a hidden input emits none of its own — which is what the
// Object section's autosave saves. `resync` runs after a morph (the wrapper's
// action) and on connect, so a morph landing during a pending save can't leave
// a stale cell pressed.
export default class extends Controller {
  static targets = ["input", "cell"]

  connect() { this.resync() }

  pick(event) {
    const value = event.currentTarget.dataset.anchor
    if (this.inputTarget.disabled || this.inputTarget.value === value) return
    this.inputTarget.value = value
    this.inputTarget.setAttribute("value", value)
    this.resync()
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  resync() {
    for (const cell of this.cellTargets) {
      cell.setAttribute("aria-pressed", String(cell.dataset.anchor === this.inputTarget.value))
    }
  }
}
