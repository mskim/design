import { test } from "node:test"
import assert from "node:assert/strict"
import { guideRects, printCookie, PRINT_COOKIE } from "../../app/javascript/design-controllers/design/page_guides.js"

// 432 × 648 pt page; margins top 50, bottom 80, left 60, right 40; binding 10.
const page = (over = {}) => ({ kind: "columns", width: 432, height: 648, top: 50, bottom: 80, left: 60, right: 40,
                               binding: 0, parity: "odd", columnCount: 1, gutter: 12, ...over })
const pct = (x, of) => 100 * x / of
const near = (a, b) => assert.ok(Math.abs(a - b) < 1e-9, `${a} ≈ ${b}`)

test("margins: the content box in percent of the page", () => {
  const { margin, binding, columns } = guideRects(page())
  near(margin.left, pct(60, 432)); near(margin.top, pct(50, 648))
  near(margin.width, pct(432 - 60 - 40, 432)); near(margin.height, pct(648 - 50 - 80, 648))
  assert.equal(binding, null, "no binding outside print mode")
  assert.deepEqual(columns, [], "one column draws no column guides")
})

test("print mode: an odd page takes the binding on the left, an even page on the right", () => {
  const odd = guideRects(page({ binding: 10, parity: "odd" }))
  near(odd.margin.left, pct(70, 432)); near(odd.margin.width, pct(432 - 70 - 40, 432))
  near(odd.binding.left, pct(60, 432)); near(odd.binding.width, pct(10, 432))
  near(odd.binding.top, 0); near(odd.binding.height, 100)
  const even = guideRects(page({ binding: 10, parity: "even" }))
  near(even.margin.left, pct(60, 432)); near(even.margin.width, pct(432 - 60 - 50, 432))
  near(even.binding.left, pct(432 - 40 - 10, 432))
})

test("columns: count boxes split by the gutter inside the content box", () => {
  const { columns } = guideRects(page({ columnCount: 2, gutter: 12 }))
  const colW = (432 - 60 - 40 - 12) / 2
  assert.equal(columns.length, 2)
  near(columns[0].left, pct(60, 432)); near(columns[0].width, pct(colW, 432))
  near(columns[1].left, pct(60 + colW + 12, 432))
  assert.deepEqual(guideRects(page({ columnCount: 3, gutter: 400 })).columns, [], "no width: no column guides")
})

test("print mode columns: an odd page starts them past the binding, an even page at the left margin", () => {
  // Content width net of the binding (10): 432 - 60 - 40 - 10 = 322; two columns and a 12 gutter.
  const colW = (432 - 60 - 40 - 10 - 12) / 2
  const odd = guideRects(page({ binding: 10, parity: "odd", columnCount: 2 })).columns
  assert.equal(odd.length, 2)
  near(odd[0].left, pct(60 + 10, 432)); near(odd[0].width, pct(colW, 432))
  near(odd[1].left, pct(60 + 10 + colW + 12, 432)); near(odd[1].width, pct(colW, 432))
  near(odd[0].top, pct(50, 648)); near(odd[0].height, pct(648 - 50 - 80, 648))
  const even = guideRects(page({ binding: 10, parity: "even", columnCount: 2 })).columns
  assert.equal(even.length, 2)
  near(even[0].left, pct(60, 432)); near(even[0].width, pct(colW, 432))
  near(even[1].left, pct(60 + colW + 12, 432))
})

test("kinds: margins only draws no columns; none draws nothing", () => {
  assert.deepEqual(guideRects(page({ kind: "margins", columnCount: 2 })).columns, [])
  assert.equal(guideRects(page({ kind: "none" })), null)
  assert.equal(guideRects(null), null)
})

test("the print cookie: set for a year, cleared with max-age=0", () => {
  assert.equal(PRINT_COOKIE, "design_preview_print")
  assert.equal(printCookie(true), "design_preview_print=1; path=/; max-age=31536000; SameSite=Lax")
  assert.equal(printCookie(false), "design_preview_print=; path=/; max-age=0; SameSite=Lax")
})
