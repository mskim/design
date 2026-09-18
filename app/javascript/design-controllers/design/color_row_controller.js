import { Controller } from "@hotwired/stimulus"
import { parseColor, cmykToHex, hexToCmyk, formatCmyk, summaryText, swatchHex, isHex } from "design-controllers/design/color_math"

// ColorField behaviour. The hidden `value` input holds the stored text ("CMYK=…" or
// "#rrggbb"); every edit rewrites it and dispatches bubbling input (while editing) and
// change (on close) from it, so the form's own listeners see a normal field change.
const CHECKERBOARD = "repeating-conic-gradient(#e2e8f0 0% 25%, #ffffff 0% 50%) 50% / 8px 8px"

export default class extends Controller {
  static targets = ["value", "trigger", "swatch", "summary", "popover", "modeButton",
                    "cmykPanel", "hexPanel", "kSlider", "hexInput", "picker"]
  static values = { formats: String, inherit: String }

  connect() {
    this.outside = (e) => { if (!this.element.contains(e.target)) this.close() }
    this.render()
  }

  disconnect() { document.removeEventListener("pointerdown", this.outside) }

  get formats() { return this.formatsValue.split(",") }

  toggle() { this.popoverTarget.hidden ? this.open() : this.close() }

  open() {
    const r = this.triggerTarget.getBoundingClientRect()
    Object.assign(this.popoverTarget.style, { left: `${r.left}px`, top: `${r.bottom + 4}px` })
    const parsed = parseColor(this.valueTarget.value)
    const mode = parsed && this.formats.includes(parsed.format) ? parsed.format : this.formats[0]
    this.showMode(mode)
    this.startValue = this.valueTarget.value
    this.popoverTarget.hidden = false
    document.addEventListener("pointerdown", this.outside)
  }

  close() {
    if (this.popoverTarget.hidden) return
    this.popoverTarget.hidden = true
    document.removeEventListener("pointerdown", this.outside)
    if (this.valueTarget.value !== this.startValue) this.emit("change")
    this.triggerTarget.focus()
  }

  // Escape reaching here means no sub-field swallowed it (scrub-input stops its own).
  keydown(event) {
    if (event.key === "Escape" && !this.popoverTarget.hidden) { event.preventDefault(); this.close() }
  }

  selectMode(event) { this.showMode(event.currentTarget.dataset.mode, { convert: true }) }

  showMode(mode, { convert = false } = {}) {
    this.mode = mode
    this.modeButtonTargets.forEach((b) => { b.toggleAttribute("data-active", b.dataset.mode === mode) })
    if (this.hasCmykPanelTarget) this.cmykPanelTarget.hidden = mode !== "cmyk"
    if (this.hasHexPanelTarget) this.hexPanelTarget.hidden = mode !== "hex"
    const hex = swatchHex(this.valueTarget.value)
    if (mode === "cmyk") {
      const p = parseColor(this.valueTarget.value)
      const cmyk = p?.format === "cmyk" ? p : (hex ? hexToCmyk(hex) : { c: 0, m: 0, y: 0, k: 0 })
      this.fillChannels(cmyk)
      if (convert && this.valueTarget.value) this.setValue(formatCmyk(cmyk))
    } else {
      this.hexInputTarget.value = hex ?? ""
      if (convert && hex) this.setValue(hex)
    }
  }

  fillChannels({ c, m, y, k }) {
    const byName = { c, m, y, k }
    this.channelInputs.forEach((i) => { i.value = String(byName[i.dataset.channel]) })
    this.kSliderTarget.value = String(k)
  }

  get channelInputs() { return this.cmykPanelTarget.querySelectorAll("input[data-channel]") }

  fromChannels(event) {
    if (event?.target === this.kSliderTarget) return
    const v = {}
    this.channelInputs.forEach((i) => {
      const n = parseFloat(i.value)
      v[i.dataset.channel] = Number.isFinite(n) ? Math.min(100, Math.max(0, n)) : 0
    })
    this.kSliderTarget.value = String(v.k)
    this.setValue(formatCmyk(v))
  }

  fromSlider() {
    const k = this.cmykPanelTarget.querySelector("input[data-channel='k']")
    k.value = this.kSliderTarget.value
    this.fromChannels()
  }

  fromHex() {
    const v = this.hexInputTarget.value.trim()
    if (isHex(v)) this.setValue(v.toLowerCase())
  }

  hexKeydown(event) { if (event.key === "Enter") { event.preventDefault(); this.fromHex() } }

  openPicker() {
    this.pickerTarget.value = swatchHex(this.valueTarget.value) ?? "#000000"
    // showPicker() is the reliable way to open a visually hidden colour input (Safari).
    if (typeof this.pickerTarget.showPicker === "function") this.pickerTarget.showPicker()
    else this.pickerTarget.click()
  }

  fromPicker() {
    this.hexInputTarget.value = this.pickerTarget.value
    this.fromHex()
  }

  clear() {
    this.setValue("")
    this.close()
  }

  setValue(v) {
    this.valueTarget.value = v
    this.render()
    this.emit("input")
  }

  render() {
    const v = this.valueTarget.value
    const hex = swatchHex(v)
    this.swatchTarget.style.background = hex ?? CHECKERBOARD
    this.summaryTarget.textContent = v.trim() === "" ? this.inheritValue : summaryText(v)
  }

  emit(type) { this.valueTarget.dispatchEvent(new Event(type, { bubbles: true })) }
}
