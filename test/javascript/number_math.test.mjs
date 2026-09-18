import { test } from "node:test"
import assert from "node:assert/strict"
import { evaluate, stepValue, clamp, formatNumber, decimalsOf } from "../../app/javascript/design-controllers/design/number_math.js"

test("plain numbers and maths", () => {
  assert.equal(evaluate("12", "pt"), 12)
  assert.equal(evaluate(" 12*1.5 ", "pt"), 18)
  assert.equal(evaluate("(20-4)/2", "pt"), 8)
  assert.equal(evaluate("-3+5", "pt"), 2)
  assert.equal(evaluate(".5", "pt"), 0.5)
})

test("invalid input returns null", () => {
  for (const bad of ["", "abc", "1+", "(2", "2)", "1/0", "alert(1)", "1,5"]) assert.equal(evaluate(bad, "pt"), null, bad)
})

test("typed units convert to the stored unit", () => {
  assert.equal(formatNumber(evaluate("5mm", "pt")), "14.17")
  assert.equal(formatNumber(evaluate("1in", "mm")), "25.4")
  assert.equal(evaluate("1p", "pt"), 12)
  assert.equal(evaluate("12pt", "pt"), 12)
  assert.equal(formatNumber(evaluate("1cm", "mm")), "10")
  assert.equal(formatNumber(evaluate("2*5 mm", "pt")), "28.35")
})

test("units are rejected for unitless and non-length fields", () => {
  assert.equal(evaluate("5mm", "none"), null)
  assert.equal(evaluate("5mm", "lines"), null)
  assert.equal(evaluate("5pt", "percent"), null)
  assert.equal(evaluate("5", "lines"), 5)
})

test("stepping honours step, modifiers and rounding", () => {
  assert.equal(stepValue(10, 0.1, 1, {}), 10.1)
  assert.equal(stepValue(10, 0.1, -1, { shift: true }), 9)
  assert.equal(stepValue(10, 0.1, 1, { alt: true }), 10.01)
  assert.equal(stepValue(0.1, 0.1, 2, {}), 0.3)          // no 0.30000000000000004
  assert.equal(stepValue(3, 1, 1, {}), 4)
})

test("clamp and decimals", () => {
  assert.equal(clamp(5, 1, 3), 3)
  assert.equal(clamp(-1, 0, null), 0)
  assert.equal(clamp(7, null, null), 7)
  assert.equal(decimalsOf(0.1), 1)
  assert.equal(decimalsOf(0.01), 2)
  assert.equal(decimalsOf(1), 0)
  assert.equal(formatNumber(14.1732), "14.17")
  assert.equal(formatNumber(10), "10")
})

test("formatNumber keeps the precision it is given", () => {
  assert.equal(formatNumber(10.001, 3), "10.001")
  assert.equal(formatNumber(10.001), "10")                         // default stays 2
  assert.equal(formatNumber(1.23456, Math.max(2, decimalsOf(0.001))), "1.235")
  assert.equal(formatNumber(1.5, Math.max(2, decimalsOf(1))), "1.5")
})

test("a percent field accepts a trailing %", () => {
  assert.equal(evaluate("50%", "percent"), 50)
  assert.equal(evaluate(" 50 % ", "percent"), 50)
  assert.equal(evaluate("40+10%", "percent"), 50)
  assert.equal(evaluate("%", "percent"), null)
  assert.equal(evaluate("50%", "pt"), null)
  assert.equal(evaluate("50%", "none"), null)
})
