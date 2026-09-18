// Four on/off flags stored as "t,r,b,l" / "tl,tr,br,bl" text ("1" on, "0"
// off) for design--border-side-editor and design--corner-editor (pure;
// node-tested). An inherited (empty) value shows — and starts toggling from —
// the parent's flags; anything short is padded with "0".

export function flagParts(value, parent) {
  const text = value || parent || ""
  const parts = text === "" ? [] : text.split(",").map((s) => s.trim())
  while (parts.length < 4) parts.push("0")
  return parts.slice(0, 4)
}

// Toggle flag `index`: always an explicit value (all off is "0,0,0,0").
export function toggleFlag(value, parent, index) {
  const parts = flagParts(value, parent)
  parts[index] = parts[index] === "1" ? "0" : "1"
  return parts.join(",")
}
