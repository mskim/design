import { test } from "node:test"
import assert from "node:assert/strict"
import { sketchValues, sketchStyle, cornerRadius, strokePx }
  from "../../app/javascript/design-controllers/design/box_sketch.js"
import { swatchHex } from "../../app/javascript/design-controllers/design/color_math.js"

const FIELDS = [ "border_top_thickness", "border_right_thickness", "border_bottom_thickness", "border_left_thickness",
                 "border_top_color", "border_right_color", "border_bottom_color", "border_left_color",
                 "corner_top_left", "corner_top_right", "corner_bottom_right", "corner_bottom_left" ]
const effective = Object.fromEntries(FIELDS.map((f) => [ f, f.endsWith("thickness") ? "1" : f.endsWith("color") ? "" : "none" ]))

test("cornerRadius follows BoxDecoration.radius: relative to the shorter side, capped at half of it", () => {
  assert.equal(cornerRadius("none", 96, 48), 0)
  assert.equal(cornerRadius("small", 96, 48), 2.88)
  assert.equal(cornerRadius("medium", 96, 48), 7.2)
  assert.equal(cornerRadius("full", 96, 48), 24)
  assert.equal(cornerRadius("small", 96, 10), 2, "the 2 minimum")
  assert.equal(cornerRadius("small", 96, 3), 1.5, "…capped at s/2")
})

test("strokePx: 0 stays 0; anything drawn is 1–4 px so a hairline shows", () => {
  assert.deepEqual([ 0, 0.1, 1.4, 2.6, 9 ].map(strokePx), [ 0, 1, 1, 3, 4 ])
})

test("sketchValues: a split control's value, else the server's effective value", () => {
  const values = sketchValues({ effective, split: { border_top_thickness: "3", border_left_color: "" }, linked: {} })
  assert.equal(values.border_top_thickness, "3")
  assert.equal(values.border_left_color, "", "empty falls back to effective (here also empty)")
  assert.equal(values.border_right_thickness, "1")
})

test("sketchValues: a linked box's non-empty linked value covers all four", () => {
  const values = sketchValues({ effective, split: { border_top_thickness: "3" },
                                linked: { border_thickness: "2", corners: "full" } })
  for (const s of [ "top", "right", "bottom", "left" ]) assert.equal(values[`border_${s}_thickness`], "2")
  assert.equal(values.corner_bottom_left, "full")
})

test("sketchStyle: widths, colours (black when empty) and radii", () => {
  const style = sketchStyle({ ...effective, border_top_thickness: "0", border_right_color: "#ff0000",
                              corner_top_left: "full" }, { width: 96, height: 48, toHex: swatchHex })
  assert.equal(style.borderTopWidth, "0px")
  assert.equal(style.borderRightWidth, "1px")
  assert.equal(style.borderRightColor, "#ff0000")
  assert.equal(style.borderLeftColor, "#000000")
  assert.equal(style.borderTopLeftRadius, "24px")
  assert.equal(style.borderBottomRightRadius, "0px")
  assert.equal(style.borderStyle, "solid")
})
