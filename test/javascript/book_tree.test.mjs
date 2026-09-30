import { test } from "node:test"
import assert from "node:assert/strict"
import { COOKIE_NAME, parseOpen, toggled, cookieFor, gridState }
  from "../../app/javascript/design-controllers/design/book_tree.js"

test("the cookie name matches Design::Views::BookTree::COOKIE", () => {
  assert.equal(COOKIE_NAME, "design_tree_open")
})

test("parseOpen reads the server's comma list; empty means nothing open", () => {
  assert.deepEqual(parseOpen("frontmatter,bodymatter"), ["frontmatter", "bodymatter"])
  assert.deepEqual(parseOpen(""), [])
  assert.deepEqual(parseOpen(undefined), [])
  assert.deepEqual(parseOpen(" bodymatter , "), ["bodymatter"])
})

test("toggled adds on open and removes on close", () => {
  assert.deepEqual(toggled(["bodymatter"], "frontmatter", true), ["bodymatter", "frontmatter"])
  assert.deepEqual(toggled(["bodymatter", "frontmatter"], "bodymatter", false), ["frontmatter"])
})

test("toggled returns the same array when nothing changes (the parse-time toggle of an open group)", () => {
  const keys = ["bodymatter"]
  assert.equal(toggled(keys, "bodymatter", true), keys)
  assert.equal(toggled(keys, "cover", false), keys)
})

test("cookieFor writes a site-wide, long-lived, Lax cookie with an encoded list", () => {
  const c = cookieFor(["frontmatter", "bodymatter"])
  assert.match(c, /^design_tree_open=frontmatter%2Cbodymatter; /)
  assert.match(c, /; path=\//)
  assert.match(c, /; max-age=\d{7,}/)
  assert.match(c, /; SameSite=Lax/)
  assert.match(cookieFor([]), /^design_tree_open=; /, "an empty list is kept (every group closed), not dropped")
})

test("gridState hides closed sections and shows the hint only when none is visible", () => {
  assert.deepEqual(gridState(["bodymatter"], ["frontmatter", "bodymatter", "rearmatter"]),
    { hidden: [true, false, true], hintHidden: true })
  assert.deepEqual(gridState(["cover"], ["frontmatter", "bodymatter"]),
    { hidden: [true, true], hintHidden: false })
  assert.deepEqual(gridState([], []), { hidden: [], hintHidden: true }, "no sections at all: nothing to expand, no hint")
})
