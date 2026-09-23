import { test } from "node:test"
import assert from "node:assert/strict"
import { saveJobs, partnerOf, partnerInput, LINKED_FIELDS, LINKED_KEY, jointFields, valuesFor, JOINT_KEY_PREFIX }
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

test("jointFields: a control Ruby marked data-joint-with is written with the fields it names", () => {
  assert.deepEqual(jointFields({ jointWith: "b c" }, "a"), [ "a", "b", "c" ], "more than one partner is supported")
  assert.deepEqual(jointFields({ jointWith: "text_box_grid_height" }, "text_box_grid_width"),
                   [ "text_box_grid_width", "text_box_grid_height" ])
  assert.deepEqual(jointFields({ jointWith: "  a   b  " }, "a"), [ "a", "b" ], "whitespace-tolerant, no duplicate")
  for (const dataset of [ {}, { jointWith: "" }, { jointWith: "   " }, undefined ]) {
    assert.equal(jointFields(dataset, "x"), null, JSON.stringify(dataset))
  }
})

test("valuesFor reads each field's value off the section's own controls, never by selector", () => {
  const fieldOf = (name) => /^object\[(\w+)\]$/.exec(name ?? "")?.[1] ?? null
  const inputs = [ { name: "object[a]", value: " 3 " }, { name: "object[b]", value: "7" },
                   { name: "paragraph_style[a]", value: "99" }, { name: "object[a]", value: "later" } ]
  assert.deepEqual(valuesFor(inputs, fieldOf, [ "a", "b" ]), { a: "3", b: "7" }, "trimmed, first match wins")
  assert.equal(valuesFor(inputs, fieldOf, [ "a", "missing" ]), null, "a set that isn't all there is not sent")
})

test("a joint commit is ONE request covering every field in the set", () => {
  const joint = { text_box_grid_width: "4", text_box_grid_height: "6" }
  const jobs = saveJobs({ field: "text_box_grid_width", value: "4", url, joint })
  assert.equal(jobs.length, 1)
  assert.deepEqual(jobs[0], { key: `${JOINT_KEY_PREFIX}text_box_grid_height,text_box_grid_width`,
                              method: "PATCH", url,
                              fields: [ "text_box_grid_width", "text_box_grid_height" ], values: joint })
  assert.equal(saveJobs({ field: "text_box_grid_height", value: "6", url,
                          joint: { text_box_grid_height: "6", text_box_grid_width: "4" } })[0].key,
               jobs[0].key,
               "the key is the set, sorted: a width commit and a height commit coalesce in the queue")
})

test("an anchor pick carries no joint set: one plain PATCH of its own field", () => {
  assert.deepEqual(saveJobs({ field: "text_box_anchor_position", value: "5", url }),
                   [ { key: "text_box_anchor_position", method: "PATCH", url,
                       field: "text_box_anchor_position", value: "5" } ])
})

test("emptying a joint field reverts that field alone", () => {
  assert.deepEqual(saveJobs({ field: "text_box_grid_width", value: "", url,
                              joint: { text_box_grid_width: "", text_box_grid_height: "6" } }),
                   [ { key: "text_box_grid_width", method: "DELETE", url, field: "text_box_grid_width" } ])
})

test("the linked margin pair is unaffected by joint sets", () => {
  assert.equal(saveJobs({ field: "left_margin_mm", value: "18", url, linked: true })[0].key, LINKED_KEY)
})
