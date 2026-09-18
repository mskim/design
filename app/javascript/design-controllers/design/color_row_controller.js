import { Controller } from "@hotwired/stimulus"
import { parseColor, hexToCmyk, formatCmyk, summaryText, swatchHex, isHex } from "design-controllers/design/color_math"

// ColorField behaviour. The hidden `value` input holds the stored text ("CMYK=…" or
// "#rrggbb"); every edit rewrites it and dispatches bubbling input (while editing) and
// change (on close) from it, so the form's own listeners see a normal field change.
// Switching modes only converts the displayed fields; the stored text changes only when
// the user edits in the new mode (a CMYK→hex→CMYK round trip would lose e.g. rich black).
const CHECKERBOARD = "repeating-conic-gradient(#e2e8f0 0% 25%, #ffffff 0% 50%) 50% / 8px 8px"
const EDGE = 8
const GAP = 4

export default class extends Controller {
  static targets = ["value", "trigger", "swatch", "summary", "popover", "modeButton",
                    "cmykPanel", "hexPanel", "kSlider", "hexInput", "picker"]
  static values = { formats: String, inherit: String, parent: String }

  connect() {
    this.outside = (e) => { if (!this.element.contains(e.target)) this.close() }
    this.onKeydown = (e) => this.keydown(e)
    this.onScroll = (e) => { if (!this.popoverTarget.contains(e.target)) this.close() }
    this.render()
  }

  disconnect() { this.unlisten() }

  get formats() { return this.formatsValue.split(",") }

  toggle() { this.popoverTarget.hidden ? this.open() : this.close() }

  open() {
    const parsed = parseColor(this.valueTarget.value || this.parentValue)
    const mode = parsed && this.formats.includes(parsed.format) ? parsed.format : this.formats[0]
    this.showMode(mode)
    this.startValue = this.valueTarget.value
    this.place()
    this.triggerTarget.setAttribute("aria-expanded", "true")
    document.addEventListener("pointerdown", this.outside)
    document.addEventListener("keydown", this.onKeydown)
    document.addEventListener("scroll", this.onScroll, true)
  }

  // Unhide invisibly to measure, then keep the popover inside the viewport: clamp the
  // left edge and flip above the trigger when there is no room below.
  place() {
    const pop = this.popoverTarget
    pop.style.visibility = "hidden"
    pop.hidden = false
    const r = this.triggerTarget.getBoundingClientRect()
    const w = pop.offsetWidth
    const h = pop.offsetHeight
    const left = Math.max(EDGE, Math.min(r.left, window.innerWidth - w - EDGE))
    const below = r.bottom + GAP
    const top = below + h > window.innerHeight ? Math.max(EDGE, r.top - GAP - h) : below
    Object.assign(pop.style, { left: `${left}px`, top: `${top}px`, visibility: "" })
  }

  // refocus: only for keyboard-ish closes (Escape, Clear); an outside click or a scroll
  // must not pull focus (or the page) back to the trigger.
  close({ refocus = false } = {}) {
    if (this.popoverTarget.hidden) return
    this.popoverTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
    this.unlisten()
    if (this.valueTarget.value !== this.startValue) this.emit("change")
    if (refocus) this.triggerTarget.focus({ preventScroll: true })
  }

  unlisten() {
    document.removeEventListener("pointerdown", this.outside)
    document.removeEventListener("keydown", this.onKeydown)
    document.removeEventListener("scroll", this.onScroll, true)
  }

  // Document-level while open. Escape inside a channel is swallowed by scrub-input
  // (stopPropagation), so the popover closes on the *next* Escape.
  keydown(event) {
    if (event.key === "Escape" && !this.popoverTarget.hidden) {
      event.preventDefault()
      this.close({ refocus: true })
    }
  }

  selectMode(event) { this.showMode(event.currentTarget.dataset.mode) }

  // Display only — never writes the stored value.
  showMode(mode) {
    this.mode = mode
    this.modeButtonTargets.forEach((b) => {
      const active = b.dataset.mode === mode
      b.toggleAttribute("data-active", active)
      b.setAttribute("aria-pressed", String(active))
    })
    if (this.hasCmykPanelTarget) this.cmykPanelTarget.hidden = mode !== "cmyk"
    if (this.hasHexPanelTarget) this.hexPanelTarget.hidden = mode !== "hex"
    if (mode === "cmyk") this.fillChannels(this.cmykFromValue())
    else this.hexInputTarget.value = swatchHex(this.valueTarget.value || this.parentValue) ?? ""
  }

  // Stored text as CMYK for display; an inherited (empty) value starts from the
  // parent's colour; nothing at all shows zeros.
  cmykFromValue() {
    const v = this.valueTarget.value.trim() === "" ? this.parentValue : this.valueTarget.value
    const p = parseColor(v)
    if (p?.format === "cmyk") return p
    const hex = swatchHex(v)
    return hex ? hexToCmyk(hex) : { c: 0, m: 0, y: 0, k: 0 }
  }

  fillChannels({ c, m, y, k }) {
    const byName = { c, m, y, k }
    this.channelInputs.forEach((i) => { i.value = String(byName[i.dataset.channel]) })
    this.kSliderTarget.value = String(k)
  }

  get channelInputs() { return this.cmykPanelTarget.querySelectorAll("input[data-channel]") }

  // focusin on the CMYK panel: the stored text a channel's Escape/invalid restores to.
  rememberField() { this.fieldStart = this.valueTarget.value }

  // design--scrub-input:revert — the channel went back to its focus-time text; put the
  // stored colour back too (an inherited empty value stays empty).
  revertField() {
    const v = this.fieldStart ?? this.valueTarget.value
    if (v !== this.valueTarget.value) this.setValue(v)
    this.fillChannels(this.cmykFromValue())
  }

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

  // A channel committed: store, then re-show what was stored (cleared → 0, maths → result).
  commitChannels(event) {
    if (event?.target === this.kSliderTarget) return
    this.fromChannels(event)
    this.fillChannels(this.cmykFromValue())
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
    // showPicker() is the reliable way to open a visually hidden colour input (Safari);
    // it throws when not allowed (no user activation, cross-origin frame), so fall back.
    try {
      if (typeof this.pickerTarget.showPicker !== "function") throw new Error("no showPicker")
      this.pickerTarget.showPicker()
    } catch {
      this.pickerTarget.click()
    }
  }

  fromPicker() {
    this.hexInputTarget.value = this.pickerTarget.value
    this.fromHex()
  }

  clear() {
    this.setValue("")
    this.close({ refocus: true })
  }

  setValue(v) {
    this.valueTarget.value = v
    this.render()
    this.emit("input")
  }

  render() {
    const v = this.valueTarget.value
    const inherited = v.trim() === ""
    const shown = inherited ? this.parentValue : v
    this.swatchTarget.style.background = swatchHex(shown) ?? CHECKERBOARD
    this.summaryTarget.textContent = inherited ? (shown ? summaryText(shown) : this.inheritValue) : summaryText(v)
    this.summaryTarget.toggleAttribute("data-inherited", inherited && shown !== "")
  }

  emit(type) { this.valueTarget.dispatchEvent(new Event(type, { bubbles: true })) }
}
