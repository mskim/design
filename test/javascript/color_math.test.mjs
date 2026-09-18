import { test } from "node:test"
import assert from "node:assert/strict"
import { parseColor, cmykToHex, hexToCmyk, formatCmyk, summaryText, swatchHex, isHex } from "../../app/javascript/design-controllers/design/color_math.js"

test("parseColor recognises CMYK, hex, names and blank", () => {
  assert.deepEqual(parseColor("CMYK=0,0,0,100"), { format: "cmyk", c: 0, m: 0, y: 0, k: 100 })
  assert.deepEqual(parseColor("#3B82F6"), { format: "hex", hex: "#3b82f6" })
  assert.deepEqual(parseColor("white"), { format: "named", name: "white", hex: "#ffffff" })
  assert.equal(parseColor(""), null)
  assert.equal(parseColor("CMYK=1,2"), null)
})

test("conversions", () => {
  assert.equal(cmykToHex({ c: 0, m: 0, y: 0, k: 100 }), "#000000")
  assert.equal(cmykToHex({ c: 0, m: 0, y: 0, k: 0 }), "#ffffff")
  assert.deepEqual(hexToCmyk("#000000"), { c: 0, m: 0, y: 0, k: 100 })
  assert.deepEqual(hexToCmyk("#ffffff"), { c: 0, m: 0, y: 0, k: 0 })
  assert.equal(formatCmyk({ c: 10, m: 0, y: 5.5, k: 20 }), "CMYK=10,0,5.5,20")
})

test("summary text matches the Ruby ColorValue.summary", () => {
  assert.equal(summaryText("CMYK=0,0,0,100"), "C0 M0 Y0 K100")
  assert.equal(summaryText("CMYK=0.0,10.0,0,43"), "C0 M10 Y0 K43")
  assert.equal(summaryText("#3B82F6"), "#3b82f6")
  assert.equal(summaryText("white"), "white")
  assert.equal(summaryText(""), "")
})

test("swatchHex and isHex", () => {
  assert.equal(swatchHex("CMYK=0,0,0,100"), "#000000")
  assert.equal(swatchHex("white"), "#ffffff")
  assert.equal(swatchHex(""), null)
  assert.ok(isHex("#a1b2c3"))
  assert.ok(!isHex("#abc"))
  assert.ok(!isHex("a1b2c3"))
})
