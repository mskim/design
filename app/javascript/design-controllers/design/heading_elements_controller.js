import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "row", "template", "typeSelect", "position", "destroy", "elementType", "styleName"]

  add() {
    const type = this.typeSelectTarget.value
    const templateRow = this.templateTarget.querySelector("[data-design--heading-elements-target='row']")
    const row = templateRow.cloneNode(true)
    const idx = Date.now() // unique index for nested attributes

    // Update field names with unique index
    row.querySelectorAll("input, select").forEach(input => {
      if (input.name) {
        input.name = input.name.replace("[IDX]", `[${idx}]`)
      }
    })

    // Set element type and style name
    const typeInput = row.querySelector("[data-design--heading-elements-target='elementType']")
    const styleInput = row.querySelector("[data-design--heading-elements-target='styleName']")
    const typeLabel = row.querySelector(".text-sm.font-medium")

    if (typeInput) typeInput.value = type
    if (styleInput) styleInput.value = type
    if (typeLabel) typeLabel.textContent = type.charAt(0).toUpperCase() + type.slice(1)

    this.listTarget.appendChild(row)
    this._updatePositions()
    this._triggerPreview()
  }

  remove(event) {
    const row = event.target.closest("[data-design--heading-elements-target='row']")
    const destroyInput = row.querySelector("[data-design--heading-elements-target='destroy']")
    const idInput = row.querySelector("input[name$='[id]']")

    if (idInput && idInput.value) {
      // Mark for destruction instead of removing from DOM
      destroyInput.value = "1"
      row.classList.add("hidden")
    } else {
      row.remove()
    }

    this._updatePositions()
    this._triggerPreview()
  }

  dragStart(event) {
    this._dragRow = event.target.closest("[data-design--heading-elements-target='row']")
    this._dragRow.classList.add("opacity-50")

    document.addEventListener("mousemove", this._dragMove)
    document.addEventListener("mouseup", this._dragEnd)
  }

  _dragMove = (event) => {
    const rows = [...this.rowTargets].filter(r => !r.classList.contains("hidden"))
    const y = event.clientY

    for (const row of rows) {
      const rect = row.getBoundingClientRect()
      const mid = rect.top + rect.height / 2
      if (y < mid && row !== this._dragRow) {
        this.listTarget.insertBefore(this._dragRow, row)
        return
      }
    }
    // If past all rows, append
    this.listTarget.appendChild(this._dragRow)
  }

  _dragEnd = () => {
    this._dragRow.classList.remove("opacity-50")
    document.removeEventListener("mousemove", this._dragMove)
    document.removeEventListener("mouseup", this._dragEnd)
    this._dragRow = null
    this._updatePositions()
    this._triggerPreview()
  }

  _updatePositions() {
    const rows = [...this.rowTargets].filter(r => !r.classList.contains("hidden"))
    rows.forEach((row, i) => {
      const posInput = row.querySelector("[data-design--heading-elements-target='position']")
      if (posInput) posInput.value = i
    })
  }

  _triggerPreview() {
    // Dispatch input event on the form to trigger live-preview controller
    const form = this.element.closest("form")
    if (form) {
      form.dispatchEvent(new Event("input", { bubbles: true }))
    }
  }
}
