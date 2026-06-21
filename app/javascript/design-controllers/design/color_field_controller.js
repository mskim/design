import { Controller } from "@hotwired/stimulus"

// Bidirectional sync between a <input type="color"> picker and a text input.
// The text input is the source of truth and accepts: CMYK=C,M,Y,K  |  #hex  |  named colors.
// The picker always shows an approximate hex preview.
export default class extends Controller {
  static targets = ["picker", "text"]

  connect() {
    this.syncPickerFromText()
  }

  // Picker → Text: convert hex to CMYK and write to text field
  pickerChanged() {
    const hex = this.pickerTarget.value
    this.textTarget.value = this.hexToCmyk(hex)
    this.textTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }

  // Text → Picker: parse text value and update the picker swatch
  textChanged() {
    this.syncPickerFromText()
  }

  // --- private helpers ---

  syncPickerFromText() {
    const hex = this.valueToHex(this.textTarget.value)
    if (hex) this.pickerTarget.value = hex
  }

  // Convert any supported color string to #hex for the picker
  valueToHex(val) {
    if (!val || val.trim() === "") return "#ffffff"
    val = val.trim()

    // Already hex
    if (val.match(/^#[0-9a-fA-F]{6}$/)) return val

    // CMYK=C,M,Y,K
    if (val.startsWith("CMYK=")) {
      const parts = val.substring(5).split(",").map(Number)
      if (parts.length === 4 && parts.every(n => !isNaN(n))) {
        return this.cmykToHex(parts[0], parts[1], parts[2], parts[3])
      }
    }

    // Named colors
    const named = {
      black: "#000000", white: "#ffffff", red: "#ff0000",
      blue: "#0000ff", green: "#008000", gray: "#808080", grey: "#808080"
    }
    if (named[val.toLowerCase()]) return named[val.toLowerCase()]

    return null
  }

  cmykToHex(c, m, y, k) {
    c /= 100; m /= 100; y /= 100; k /= 100
    const r = Math.round((1 - c) * (1 - k) * 255)
    const g = Math.round((1 - m) * (1 - k) * 255)
    const b = Math.round((1 - y) * (1 - k) * 255)
    return "#" + [r, g, b].map(v => Math.max(0, Math.min(255, v)).toString(16).padStart(2, "0")).join("")
  }

  hexToCmyk(hex) {
    const r = parseInt(hex.substring(1, 3), 16) / 255
    const g = parseInt(hex.substring(3, 5), 16) / 255
    const b = parseInt(hex.substring(5, 7), 16) / 255
    const k = 1 - Math.max(r, g, b)
    if (k >= 1) return "CMYK=0,0,0,100"
    const c = Math.round((1 - r - k) / (1 - k) * 100)
    const m = Math.round((1 - g - k) / (1 - k) * 100)
    const y = Math.round((1 - b - k) / (1 - k) * 100)
    return `CMYK=${c},${m},${y},${Math.round(k * 100)}`
  }
}
