import { test } from "node:test"
import assert from "node:assert/strict"
import { saveJobs, partnerOf, partnerInput, LINKED_FIELDS, LINKED_KEY }
  from "../../app/javascript/design-controllers/design/field_save_jobs.js"

const url = "/p/field"

test("a value is one PATCH; empty is one DELETE (the style panel's behaviour)", () => {
  assert.deepEqual(saveJobs({ field: "font_size", value: "12", url }),
                   [ { key: "font_size", method: "PATCH", url, field: "font_size", value: "12" } ])
  assert.deepEqual(saveJobs({ field: "font_size", value: "", url }),
                   [ { key: "font_size", method: "DELETE", url, field: "font_size" } ])
})

test("an empty required field PATCHes \"\" (the server answers 422 필수) instead of reverting", () => {
  assert.deepEqual(saveJobs({ field: "gutter", value: "", url, required: [ "column_count", "gutter" ] }),
                   [ { key: "gutter", method: "PATCH", url, field: "gutter", value: "" } ])
})

test("link on: a Left or Right value sets both in one request covering both fields", () => {
  for (const field of LINKED_FIELDS) {
    const jobs = saveJobs({ field, value: "18", url, linked: true })
    assert.equal(jobs.length, 1)
    assert.deepEqual(jobs[0], { key: LINKED_KEY, method: "PATCH", url, fields: [ "left_margin_mm", "right_margin_mm" ],
                                values: { left_margin_mm: "18", right_margin_mm: "18" } })
  }
})

test("link on: emptying Left or Right reverts both; other fields are unaffected by the link", () => {
  assert.deepEqual(saveJobs({ field: "right_margin_mm", value: "", url, linked: true }).map((j) => [ j.method, j.field ]),
                   [ [ "DELETE", "left_margin_mm" ], [ "DELETE", "right_margin_mm" ] ])
  assert.deepEqual(saveJobs({ field: "top_margin_mm", value: "20", url, linked: true }),
                   [ { key: "top_margin_mm", method: "PATCH", url, field: "top_margin_mm", value: "20" } ])
})

test("link off: Left and Right save on their own", () => {
  assert.deepEqual(saveJobs({ field: "left_margin_mm", value: "18", url, linked: false }),
                   [ { key: "left_margin_mm", method: "PATCH", url, field: "left_margin_mm", value: "18" } ])
})

test("partnerOf pairs Left and Right only", () => {
  assert.equal(partnerOf("left_margin_mm"), "right_margin_mm")
  assert.equal(partnerOf("right_margin_mm"), "left_margin_mm")
  assert.equal(partnerOf("top_margin_mm"), null)
})

test("partnerInput finds the partner by its field name, never by building a selector", () => {
  const fieldOf = (name) => name?.match(/^page\[([a-z_]+)\]$/)?.[1] ?? null
  const left = { name: "page[left_margin_mm]" }
  const right = { name: "page[right_margin_mm]" }
  const inputs = [ { name: "page[top_margin_mm]" }, { name: 'x"] , [name="page[right_margin_mm]' }, left, right ]
  assert.equal(partnerInput(inputs, fieldOf, "left_margin_mm"), right)
  assert.equal(partnerInput(inputs, fieldOf, "right_margin_mm"), left)
  assert.equal(partnerInput(inputs, fieldOf, "top_margin_mm"), null, "no partner")
  assert.equal(partnerInput([ left ], fieldOf, "left_margin_mm"), null, "partner not rendered")
})
