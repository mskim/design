import { Controller } from "@hotwired/stimulus"
import { evaluate, stepValue, clamp, formatNumber, roundTo, decimalsOf } from "design-controllers/design/number_math"

// NumberField behaviour: drag the label to scrub (Shift ×10, Alt ÷10), arrows to step,
// typed maths/units on commit, Escape to restore, Enter commits without submitting.
// Dispatches bubbling `input` while scrubbing/stepping and `change` on commit, so the
// properties panel's live preview (listening on the form) updates as you drag. Resets
// (Escape, an invalid commit) also emit `input`/`change` and `design--scrub-input:revert`
// so listeners see the restored value. Nothing is emitted when nothing changed.
const PX_PER_STEP = 2

export default class extends Controller {
  static targets = ["input", "handle"]
  static values = { unit: String, step: Number, min: Number, max: Number }

  connect() { this.lastGood = this.inputTarget.value }

  disconnect() {
    clearTimeout(this.invalidTimer)
    this.invalidTimer = null
    this.drag = null
  }

  get bounds() {
    return [this.hasMinValue ? this.minValue : null, this.hasMaxValue ? this.maxValue : null]
  }

  // The field's current number: typed maths/units first ("12*2" → 24, "5mm" → pt),
  // then the placeholder (the inherited value), then 0.
  get startNumber() {
    const typed = evaluate(this.inputTarget.value, this.unitValue)
    if (typed !== null) return typed
    const p = parseFloat(this.inputTarget.placeholder)
    return Number.isFinite(p) ? p : 0
  }

  // Integer fields (step >= 1: counts, grid cells, %) never go fractional with Alt.
  get fineAllowed() { return this.stepValue < 1 }

  effectiveStep(event) {
    return this.stepValue * (event.shiftKey ? 10 : (this.fineAllowed && event.altKey) ? 0.1 : 1)
  }

  // Display precision for a step: at least 2 decimals, more when the step needs them.
  precisionFor(step) { return Math.max(2, decimalsOf(step)) }

  // Typed values keep the finest step's precision (an Alt-stepped value survives commit).
  get commitPrecision() { return this.precisionFor(this.fineAllowed ? this.stepValue * 0.1 : this.stepValue) }

  // Values set by code after connect() (e.g. the colour row filling its channels) become
  // the baseline, so a focus/blur pass without edits stays a no-op.
  remember() { this.focusValue = this.lastGood = this.inputTarget.value }

  keydown(event) {
    if (event.key === "ArrowUp" || event.key === "ArrowDown") {
      event.preventDefault()
      const eff = this.effectiveStep(event)
      this.setNumber(stepValue(this.startNumber, this.stepValue, event.key === "ArrowUp" ? 1 : -1,
                               { shift: event.shiftKey, alt: this.fineAllowed && event.altKey }), "input", eff)
    } else if (event.key === "Enter") {
      event.preventDefault() // commit the field; never submit the form
      this.commit()
    } else if (event.key === "Escape") {
      event.preventDefault()
      event.stopPropagation() // an enclosing popover closes on the *next* Escape
      const restored = this.focusValue ?? this.lastGood
      if (this.inputTarget.value !== restored) { this.inputTarget.value = restored; this.emit("input") }
      if (restored !== this.lastGood) { this.lastGood = restored; this.emit("change") }
      this.revert()
      this.inputTarget.blur()
    }
  }

  commit() {
    const text = this.inputTarget.value.trim()
    if (text === this.lastGood) { this.inputTarget.value = text; return } // untouched: keep server text such as "10.0"
    if (text === "") { // blank = inherit
      this.lastGood = ""
      this.emit("change")
      return
    }
    const n = evaluate(text, this.unitValue)
    if (n === null) {
      this.flashInvalid()
      this.inputTarget.value = this.lastGood
      this.emit("input")
      this.revert()
      return
    }
    const [min, max] = this.bounds
    const formatted = formatNumber(clamp(n, min, max), this.commitPrecision)
    if (formatted !== this.inputTarget.value) { this.inputTarget.value = formatted; this.emit("input") }
    if (formatted !== this.lastGood) { this.lastGood = formatted; this.emit("change") }
  }

  // turbo:morph-element — after a morph re-rendered this field (e.g. × reverted
  // it), the new text becomes the baseline, unless the field is dirty (typing
  // or a scrub-drag not yet committed): then the text differs from the
  // committed `value` attribute and the morph left it alone.
  resync(event) {
    if (event.target !== this.inputTarget) return
    const v = this.inputTarget.value
    if (v === (this.inputTarget.getAttribute("value") ?? "")) this.lastGood = this.focusValue = v
  }

  scrubStart(event) {
    if (this.inputTarget.disabled || event.button !== 0) return
    event.preventDefault()
    this.justScrubbed = false
    this.handleTarget.setPointerCapture?.(event.pointerId)
    this.drag = { pointerId: event.pointerId, x: event.clientX, base: this.startNumber,
                  eff: this.effectiveStep(event), moved: false }
  }

  scrubMove(event) {
    const drag = this.drag
    if (!drag || event.pointerId !== drag.pointerId) return
    if (event.buttons === 0) { this.scrubEnd(event); return } // the release was missed
    const eff = this.effectiveStep(event)
    if (eff !== drag.eff) { // modifier changed mid-drag: continue from here, no jump
      drag.x = event.clientX
      drag.base = this.startNumber
      drag.eff = eff
    }
    const steps = Math.trunc((event.clientX - drag.x) / PX_PER_STEP)
    if (steps === 0 && !drag.moved) return
    drag.moved = true
    this.setNumber(roundTo(drag.base + steps * eff, decimalsOf(eff)), "input", eff)
  }

  scrubEnd(event) {
    const drag = this.drag
    if (!drag || (event.pointerId !== undefined && event.pointerId !== drag.pointerId)) return
    this.drag = null
    if (this.handleTarget.hasPointerCapture?.(drag.pointerId)) this.handleTarget.releasePointerCapture(drag.pointerId)
    if (drag.moved) {
      this.justScrubbed = true // swallow the label click that follows, so the input isn't focused
      if (this.inputTarget.value !== this.lastGood) { this.lastGood = this.inputTarget.value; this.emit("change") }
    } else if (event.type === "pointerup") {
      this.inputTarget.focus()
      this.inputTarget.select()
    }
  }

  handleClick(event) {
    if (this.justScrubbed) {
      event.preventDefault()
      this.justScrubbed = false
    }
  }

  setNumber(n, eventType, step = this.stepValue) {
    const [min, max] = this.bounds
    const formatted = formatNumber(clamp(n, min, max), this.precisionFor(step))
    if (formatted === this.inputTarget.value) return
    this.inputTarget.value = formatted
    this.emit(eventType)
  }

  emit(type) { this.inputTarget.dispatchEvent(new Event(type, { bubbles: true })) }

  // `design--scrub-input:revert` lets a container restore its own state after a reset.
  revert() { this.dispatch("revert", { detail: { value: this.inputTarget.value } }) }

  flashInvalid() {
    this.element.dataset.invalid = ""
    this.inputTarget.setAttribute("aria-invalid", "true")
    clearTimeout(this.invalidTimer)
    this.invalidTimer = setTimeout(() => {
      delete this.element.dataset.invalid
      this.inputTarget.removeAttribute("aria-invalid")
    }, 600)
  }
}
