import { Controller } from "@hotwired/stimulus"
import { evaluate, stepValue, clamp, formatNumber, roundTo, decimalsOf } from "design-controllers/design/number_math"

// NumberField behaviour: drag the label to scrub (Shift ×10, Alt ÷10), arrows to step,
// typed maths/units on commit, Escape to restore, Enter commits without submitting.
// Dispatches bubbling `input` while scrubbing/stepping and `change` on commit, so the
// properties panel's live preview (listening on the form) updates as you drag.
const PX_PER_STEP = 2

export default class extends Controller {
  static targets = ["input", "handle"]
  static values = { unit: String, step: Number, min: Number, max: Number }

  connect() { this.lastGood = this.inputTarget.value }

  get bounds() {
    return [this.hasMinValue ? this.minValue : null, this.hasMaxValue ? this.maxValue : null]
  }

  get startNumber() {
    const v = parseFloat(this.inputTarget.value)
    if (Number.isFinite(v)) return v
    const p = parseFloat(this.inputTarget.placeholder)
    return Number.isFinite(p) ? p : 0
  }

  // Integer fields (step >= 1: counts, grid cells, %) never go fractional with Alt.
  get fineAllowed() { return this.stepValue < 1 }

  remember() { this.focusValue = this.inputTarget.value }

  keydown(event) {
    if (event.key === "ArrowUp" || event.key === "ArrowDown") {
      event.preventDefault()
      this.setNumber(stepValue(this.startNumber, this.stepValue, event.key === "ArrowUp" ? 1 : -1,
                               { shift: event.shiftKey, alt: this.fineAllowed && event.altKey }), "input")
    } else if (event.key === "Enter") {
      event.preventDefault() // commit the field; never submit the form
      this.commit()
    } else if (event.key === "Escape") {
      event.preventDefault()
      event.stopPropagation() // an enclosing popover closes on the *next* Escape
      this.inputTarget.value = this.focusValue ?? this.lastGood
      this.lastGood = this.inputTarget.value
      this.inputTarget.blur()
    }
  }

  commit() {
    const text = this.inputTarget.value.trim()
    if (text === "") { // blank = inherit
      if (this.lastGood !== "") { this.lastGood = ""; this.emit("change") }
      return
    }
    const n = evaluate(text, this.unitValue)
    if (n === null) { this.flashInvalid(); this.inputTarget.value = this.lastGood; return }
    const [min, max] = this.bounds
    const formatted = formatNumber(clamp(n, min, max))
    this.inputTarget.value = formatted
    if (formatted !== this.lastGood) { this.lastGood = formatted; this.emit("change") }
  }

  scrubStart(event) {
    if (this.inputTarget.disabled || event.button !== 0) return
    event.preventDefault()
    this.handleTarget.setPointerCapture(event.pointerId)
    this.drag = { x: event.clientX, base: this.startNumber, moved: false }
  }

  scrubMove(event) {
    if (!this.drag) return
    const steps = Math.trunc((event.clientX - this.drag.x) / PX_PER_STEP)
    if (steps === 0 && !this.drag.moved) return
    this.drag.moved = true
    const eff = this.stepValue * (event.shiftKey ? 10 : (this.fineAllowed && event.altKey) ? 0.1 : 1)
    this.setNumber(roundTo(this.drag.base + steps * eff, decimalsOf(eff)), "input")
  }

  scrubEnd(event) {
    if (!this.drag) return
    const moved = this.drag.moved
    this.drag = null
    if (this.handleTarget.hasPointerCapture?.(event.pointerId)) this.handleTarget.releasePointerCapture(event.pointerId)
    if (moved) { this.lastGood = this.inputTarget.value; this.emit("change") }
    else { this.inputTarget.focus(); this.inputTarget.select() }
  }

  setNumber(n, eventType) {
    const [min, max] = this.bounds
    this.inputTarget.value = formatNumber(clamp(n, min, max))
    this.emit(eventType)
  }

  emit(type) { this.inputTarget.dispatchEvent(new Event(type, { bubbles: true })) }

  flashInvalid() {
    this.element.dataset.invalid = ""
    clearTimeout(this.invalidTimer)
    this.invalidTimer = setTimeout(() => delete this.element.dataset.invalid, 600)
  }
}
