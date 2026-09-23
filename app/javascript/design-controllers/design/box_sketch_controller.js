import { Controller } from "@hotwired/stimulus"
import { sketchValues, sketchStyle } from "design-controllers/design/box_sketch"
import { swatchHex } from "design-controllers/design/color_math"

// Redraws the 테두리 section's sketch from its controls (D5): the split
// controls' values, a linked box's linked value, and — for whatever is left
// empty — the effective values the server rendered.
export default class extends Controller {
  static targets = [ "box" ]
  static values = { effective: Object }

  connect() { this.redraw() }

  disconnect() { cancelAnimationFrame(this.frame) }

  // Bound to input/change/click and to turbo:morph-element, which bubbles up
  // from every morphed descendant — one save would otherwise redraw dozens of
  // times. Coalesce to one redraw per frame.
  draw() {
    cancelAnimationFrame(this.frame)
    this.frame = requestAnimationFrame(() => this.redraw())
  }

  redraw() {
    if (!this.hasBoxTarget) return
    const split = {}
    const linked = {}
    for (const input of this.element.querySelectorAll("[name]")) {
      const field = /^paragraph_style\[(\w+)\]$/.exec(input.name)?.[1]
      if (field && field in this.effectiveValue) split[field] = input.value
      const group = /^paragraph_style_link\[(\w+)\]$/.exec(input.name)?.[1]
      if (group && input.closest("[data-link-box]")?.dataset.linked === "true") linked[group] = input.value
    }
    const rect = this.boxTarget.getBoundingClientRect()
    const style = sketchStyle(sketchValues({ effective: this.effectiveValue, split, linked }),
                              { width: rect.width || 96, height: rect.height || 48, toHex: swatchHex })
    Object.assign(this.boxTarget.style, style)
  }
}
