import { test } from "node:test"
import assert from "node:assert/strict"
import { flagParts, toggleFlag } from "../../app/javascript/design-controllers/design/edge_flags.js"

test("flagParts: own value, else the parent's, else all off; always 4 entries", () => {
  assert.deepEqual(flagParts("1,0,1,0", "0,0,0,0"), [ "1", "0", "1", "0" ])
  assert.deepEqual(flagParts("", "1,1,0,0"), [ "1", "1", "0", "0" ])
  assert.deepEqual(flagParts("", ""), [ "0", "0", "0", "0" ])
  assert.deepEqual(flagParts(undefined, undefined), [ "0", "0", "0", "0" ])
  assert.deepEqual(flagParts("1, 1", ""), [ "1", "1", "0", "0" ], "short values are padded with 0")
})

test("toggleFlag starts from the parent when inherited", () => {
  assert.equal(toggleFlag("", "1,0,0,0", 2), "1,0,1,0")
  assert.equal(toggleFlag("0,1,0,0", "1,1,1,1", 1), "0,0,0,0", "own value wins over the parent")
})

test("toggleFlag pads a short value before toggling", () => {
  assert.equal(toggleFlag("1", "", 3), "1,0,0,1")
  assert.equal(toggleFlag("", "", 0), "1,0,0,0")
})

test("toggleFlag turning the last flag off gives 0,0,0,0 (not inherit)", () => {
  assert.equal(toggleFlag("0,0,1,0", "", 2), "0,0,0,0")
})
