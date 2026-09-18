// Pure number helpers for the design--scrub-input controller (no DOM; tested with
// node --test). Lengths convert through points: 1 in = 72 pt = 25.4 mm, 1 p = 12 pt.
const PT_PER = { pt: 1, p: 12, in: 72, mm: 72 / 25.4, cm: 720 / 25.4 }
const LENGTH_FIELDS = new Set(["pt", "mm"])
const UNIT_SUFFIX = /^(.*?)\s*(pt|mm|cm|in|p)$/

// "12*1.5" → 18; "5mm" in a pt field → 14.17…; "50%" in a percent field → 50;
// null when invalid or not allowed.
export function evaluate(text, fieldUnit) {
  let src = String(text ?? "").trim().toLowerCase()
  if (fieldUnit === "percent") src = src.replace(/\s*%$/, "")
  if (src === "") return null
  let factor = 1
  const m = src.match(UNIT_SUFFIX)
  if (m) {
    if (!LENGTH_FIELDS.has(fieldUnit)) return null
    src = m[1]
    factor = PT_PER[m[2]] / PT_PER[fieldUnit]
  }
  const value = parseExpression(src)
  return value === null ? null : value * factor
}

// Recursive descent over + - * / ( ) and decimals. No eval.
function parseExpression(src) {
  const tokens = src.match(/\d+\.?\d*|\.\d+|[-+*/()]|\S/g)
  if (!tokens) return null
  let i = 0
  const peek = () => tokens[i]
  const next = () => tokens[i++]
  function expr() {
    let v = term()
    while (v !== null && (peek() === "+" || peek() === "-")) {
      const op = next(); const r = term()
      if (r === null) return null
      v = op === "+" ? v + r : v - r
    }
    return v
  }
  function term() {
    let v = factor()
    while (v !== null && (peek() === "*" || peek() === "/")) {
      const op = next(); const r = factor()
      if (r === null) return null
      v = op === "*" ? v * r : v / r
    }
    return v
  }
  function factor() {
    const t = next()
    if (t === "-") { const v = factor(); return v === null ? null : -v }
    if (t === "+") return factor()
    if (t === "(") { const v = expr(); return next() === ")" ? v : null }
    if (t !== undefined && /^(\d+\.?\d*|\.\d+)$/.test(t)) return parseFloat(t)
    return null
  }
  const result = expr()
  if (result === null || i !== tokens.length || !Number.isFinite(result)) return null
  return result
}

export function decimalsOf(step) {
  const s = String(Number(Number(step).toFixed(10)))
  return s.includes(".") ? s.split(".")[1].length : 0
}

export function roundTo(value, decimals) {
  return Number(Number(value).toFixed(decimals))
}

// One arrow/scrub step: Shift ×10, Alt ÷10, rounded to the effective step's decimals.
export function stepValue(current, step, direction, { shift = false, alt = false } = {}) {
  const eff = step * (shift ? 10 : alt ? 0.1 : 1)
  return roundTo(Number(current) + eff * direction, decimalsOf(eff))
}

export function clamp(value, min, max) {
  let v = value
  if (min !== null && min !== undefined && v < min) v = min
  if (max !== null && max !== undefined && v > max) v = max
  return v
}

// Display form: at most `decimals` places, no trailing zeros. Callers pass
// Math.max(2, decimalsOf(effectiveStep)) so a fine step's digits survive.
export function formatNumber(value, decimals = 2) {
  return String(roundTo(value, decimals))
}
