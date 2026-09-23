// The style panel's box sketch (D5; pure, node-tested): what a paragraph box
// with these twelve border/corner values roughly looks like, as CSS. The
// corner maths mirrors DocProcessorRb::BoxDecoration.radius.

const SIDES = [ "top", "right", "bottom", "left" ]
const CORNERS = [ "top_left", "top_right", "bottom_right", "bottom_left" ]
const GROUPS = { border_thickness: SIDES.map((s) => `border_${s}_thickness`),
                 border_color: SIDES.map((s) => `border_${s}_color`),
                 corners: CORNERS.map((c) => `corner_${c}`) }
const camel = (s) => s.replace(/_(\w)/g, (_, c) => c.toUpperCase())

export function cornerRadius(preset, width, height) {
  const s = Math.min(width, height)
  if (!(s > 0)) return 0
  const r = { small: Math.max(s * 0.06, 2), medium: Math.max(s * 0.15, 4), full: s * 0.5 }[preset] ?? 0
  return Math.round(Math.min(r, s * 0.5) * 100) / 100
}

export function strokePx(pt) {
  const n = Number(pt)
  if (!(n > 0)) return 0
  return Math.min(4, Math.max(1, Math.round(n)))
}

// Per field: a linked group's non-empty value (while its box is linked),
// else the split control's non-empty value, else the server's effective value.
export function sketchValues({ effective, split, linked }) {
  const values = { ...effective }
  for (const [ field, value ] of Object.entries(split)) if (String(value ?? "").trim() !== "") values[field] = value
  for (const [ group, value ] of Object.entries(linked)) {
    if (String(value ?? "").trim() === "") continue
    for (const field of GROUPS[group] ?? []) values[field] = value
  }
  return values
}

// toHex: a stored colour → "#rrggbb" or null (color_math.js#swatchHex); a
// side with no readable colour is black, as the engine draws it.
export function sketchStyle(values, { width, height, toHex }) {
  const style = { borderStyle: "solid" }
  for (const s of SIDES) {
    style[camel(`border_${s}_width`)] = `${strokePx(values[`border_${s}_thickness`])}px`
    style[camel(`border_${s}_color`)] = toHex(values[`border_${s}_color`]) || "#000000"
  }
  for (const c of CORNERS) style[camel(`border_${c}_radius`)] = `${cornerRadius(values[`corner_${c}`], width, height)}px`
  return style
}
