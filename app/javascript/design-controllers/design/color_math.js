// Pure colour helpers for design--color-row (no DOM; tested with node --test).
// Stored values are text: "CMYK=c,m,y,k" (0–100) or "#rrggbb"; legacy names are read only.
// summaryText must match Design::Views::Inputs::ColorValue.summary (Ruby).
const NAMED = { black: "#000000", white: "#ffffff", red: "#ff0000", blue: "#0000ff", green: "#008000", gray: "#808080" }

export function isHex(str) { return /^#[0-9a-fA-F]{6}$/.test(String(str ?? "").trim()) }

export function parseColor(str) {
  const s = String(str ?? "").trim()
  if (s === "") return null
  if (s.startsWith("CMYK=")) {
    const raw = s.slice(5).split(",")
    if (raw.length !== 4 || raw.some((p) => p.trim() === "")) return null // Number("") is 0; Ruby's Float("") fails
    const parts = raw.map(Number)
    if (parts.some(Number.isNaN)) return null
    const [c, m, y, k] = parts
    return { format: "cmyk", c, m, y, k }
  }
  if (isHex(s)) return { format: "hex", hex: s.toLowerCase() }
  const name = s.toLowerCase()
  if (NAMED[name]) return { format: "named", name, hex: NAMED[name] }
  return null
}

const byte = (v) => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, "0")

export function cmykToHex({ c, m, y, k }) {
  const f = (v) => v / 100
  return "#" + byte((1 - f(c)) * (1 - f(k)) * 255) + byte((1 - f(m)) * (1 - f(k)) * 255) + byte((1 - f(y)) * (1 - f(k)) * 255)
}

export function hexToCmyk(hex) {
  const r = parseInt(hex.slice(1, 3), 16) / 255
  const g = parseInt(hex.slice(3, 5), 16) / 255
  const b = parseInt(hex.slice(5, 7), 16) / 255
  const k = 1 - Math.max(r, g, b)
  if (k >= 1) return { c: 0, m: 0, y: 0, k: 100 }
  const pct = (v) => Math.round(v * 100)
  return { c: pct((1 - r - k) / (1 - k)), m: pct((1 - g - k) / (1 - k)), y: pct((1 - b - k) / (1 - k)), k: pct(k) }
}

// One decimal, trailing ".0" dropped; same rounding as ColorValue.num in Ruby.
const num = (v) => String(Math.round(Number(v) * 10) / 10)

export function formatCmyk({ c, m, y, k }) { return `CMYK=${num(c)},${num(m)},${num(y)},${num(k)}` }

export function summaryText(str) {
  const p = parseColor(str)
  if (!p) return String(str ?? "").trim()
  if (p.format === "cmyk") return `C${num(p.c)} M${num(p.m)} Y${num(p.y)} K${num(p.k)}`
  if (p.format === "hex") return p.hex
  return p.name
}

export function swatchHex(str) {
  const p = parseColor(str)
  if (!p) return null
  return p.format === "cmyk" ? cmykToHex(p) : p.hex
}
