import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "picker", "mode"]

  connect() {
    this.syncPickerFromInput()
  }

  modeChanged() {
    const mode = this.modeTarget.value
    const current = this.inputTarget.value
    if (mode === "hex") {
      this.inputTarget.value = this.toHex(current)
    } else if (mode === "cmyk") {
      this.inputTarget.value = this.toCmyk(current)
    }
  }

  pickerChanged() {
    const hex = this.pickerTarget.value
    const mode = this.modeTarget.value
    this.inputTarget.value = mode === "cmyk" ? this.hexToCmyk(hex) : hex
  }

  textChanged() {
    this.syncPickerFromInput()
  }

  syncPickerFromInput() {
    this.pickerTarget.value = this.toHex(this.inputTarget.value)
  }

  toHex(val) {
    if (!val) return "#000000"
    if (val.startsWith("#")) return val
    if (val.startsWith("CMYK=")) return this.cmykToHex(val)
    const names = { black: "#000000", white: "#ffffff", red: "#ff0000", blue: "#0000ff", green: "#008000", gray: "#808080" }
    return names[val.toLowerCase()] || "#000000"
  }

  toCmyk(val) {
    if (!val) return "CMYK=0,0,0,100"
    if (val.startsWith("CMYK=")) return val
    return this.hexToCmyk(this.toHex(val))
  }

  cmykToHex(cmyk) {
    const parts = cmyk.replace("CMYK=", "").split(",").map(Number)
    if (parts.length !== 4) return "#000000"
    const [c, m, y, k] = parts.map(v => v / 100)
    const r = Math.round((1 - c) * (1 - k) * 255)
    const g = Math.round((1 - m) * (1 - k) * 255)
    const b = Math.round((1 - y) * (1 - k) * 255)
    return `#${r.toString(16).padStart(2, "0")}${g.toString(16).padStart(2, "0")}${b.toString(16).padStart(2, "0")}`
  }

  hexToCmyk(hex) {
    const r = parseInt(hex.slice(1, 3), 16) / 255
    const g = parseInt(hex.slice(3, 5), 16) / 255
    const b = parseInt(hex.slice(5, 7), 16) / 255
    const k = 1 - Math.max(r, g, b)
    if (k === 1) return "CMYK=0,0,0,100"
    const c = Math.round((1 - r - k) / (1 - k) * 100)
    const m = Math.round((1 - g - k) / (1 - k) * 100)
    const y = Math.round((1 - b - k) / (1 - k) * 100)
    return `CMYK=${c},${m},${y},${Math.round(k * 100)}`
  }
}
