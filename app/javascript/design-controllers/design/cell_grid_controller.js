import { Controller } from "@hotwired/stimulus"
import { anchorCell, cellRect, dragSize, pointerCells } from "design-controllers/design/cell_grid"

// The Object section's mini grid, declared on the group that holds the anchor
// grid, the cell-size fields and the sketch. It keeps the sketch in step with
// those controls (its group's change/input, and a morph of the group) and, from
// the handle, resizes the box by whole cells with the anchor fixed.
//
// A drag writes both size fields and dispatches ONE `change`, from the width
// field, which carries data-joint-with: the autosave then writes width and
// height in a single validated request. The fields' own scrub controllers catch
// up with the written value on the response morph or the next focus, exactly as
// the linked margin pair does (D3).
export default class extends Controller {
  static targets = ["grid", "box", "handle", "widthInput", "heightInput", "anchorInput"]
  static values = { columns: Number, rows: Number }

  connect() {
    this.dragging = false
    this.changed = false
    this.draw()
  }

  draw() {
    if (!this.hasBoxTarget) return
    const size = this.size
    const rect = cellRect(this.grid, anchorCell(this.grid, this.anchor, size.w, size.h))
    Object.assign(this.boxTarget.style, { left: `${rect.left}%`, top: `${rect.top}%`,
                                          width: `${rect.width}%`, height: `${rect.height}%` })
  }

  dragStart(event) {
    if (!this.hasHandleTarget || !this.hasWidthInputTarget || this.widthInputTarget.disabled) return
    event.preventDefault()
    this.dragging = true
    this.changed = false
    this.handleTarget.setPointerCapture?.(event.pointerId)
  }

  dragMove(event) {
    if (!this.dragging) return
    event.preventDefault()
    const box = this.gridTarget.getBoundingClientRect()
    const pointer = pointerCells({ left: box.left, top: box.top, width: box.width, height: box.height, ...this.grid },
                                 event.clientX, event.clientY)
    this.setSize(dragSize({ ...this.grid, anchor: this.anchor, pointer }))
    this.draw()
  }

  dragEnd(event) {
    if (!this.dragging) return
    this.dragging = false
    this.handleTarget.releasePointerCapture?.(event.pointerId)
    if (!this.changed) return
    this.changed = false
    this.widthInputTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  setSize({ w, h }) {
    if (this.hasWidthInputTarget) this.changed = this.write(this.widthInputTarget, w) || this.changed
    if (this.hasHeightInputTarget) this.changed = this.write(this.heightInputTarget, h) || this.changed
  }

  write(input, cells) {
    const value = String(cells)
    if (!input || input.value === value) return false
    input.value = value
    input.setAttribute("value", value)
    return true
  }

  get grid() { return { columns: this.columnsValue, rows: this.rowsValue } }
  get anchor() { return this.hasAnchorInputTarget ? Number(this.anchorInputTarget.value) : 1 }

  // A Stimulus target getter THROWS when the target is missing, so ask with
  // has…Target rather than reaching for `?.`, which would never short-circuit.
  get size() {
    return { w: this.hasWidthInputTarget ? Number(this.widthInputTarget.value) || 1 : 1,
             h: this.hasHeightInputTarget ? Number(this.heightInputTarget.value) || 1 : 1 }
  }
}
