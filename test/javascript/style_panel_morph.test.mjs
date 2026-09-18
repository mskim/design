import { test } from "node:test"
import assert from "node:assert/strict"
import { fieldFromName, keepsLocalValue, isDirty, LocalValueKeeper, dropStreamsFor, PANEL_TARGET }
  from "../../app/javascript/design-controllers/design/style_panel_morph.js"

// Stand-ins for the DOM pieces the rules read (no DOM in node).
function input(name, attr, value = attr) {
  const attrs = new Map(attr === null ? [] : [ [ "value", attr ] ])
  return { tagName: "INPUT", name, value,
           getAttribute: (n) => attrs.get(n) ?? null, setAttribute: (n, v) => attrs.set(n, v), removeAttribute: (n) => attrs.delete(n) }
}
function select(name, options, value) {
  const opts = options.map(([ v, selected ]) => ({ value: v, selected }))
  return { tagName: "SELECT", name, value, options: opts,
           querySelector: (sel) => sel === "option[selected]" ? (opts.find((o) => o.selected) ?? null) : null }
}

test("fieldFromName accepts only paragraph_style[<field>]", () => {
  assert.equal(fieldFromName("paragraph_style[font_size]"), "font_size")
  for (const name of [ "preview_mode", "authenticity_token", "", undefined, null, "document_design[gutter]", "paragraph_style[a][b]" ]) {
    assert.equal(fieldFromName(name), null, String(name))
  }
})

test("keepsLocalValue: an unanswered save or an uncommitted (dirty) value keeps the local value", () => {
  assert.equal(keepsLocalValue({ pending: true, dirty: false }), true)
  assert.equal(keepsLocalValue({ pending: false, dirty: true }), true, "typing, or a scrub-drag (never focused)")
  assert.equal(keepsLocalValue({ pending: false, dirty: false }), false, "committed: take the server's value")
})

test("isDirty compares the live value with the committed value attribute / option[selected]", () => {
  assert.equal(isDirty(input("paragraph_style[font_size]", "10", "10")), false)
  assert.equal(isDirty(input("paragraph_style[font_size]", "10", "15")), true)
  assert.equal(isDirty(input("paragraph_style[font_size]", null, "")), false, "no attribute = blank")
  assert.equal(isDirty(select("paragraph_style[text_align]", [ [ "", false ], [ "center", true ] ], "center")), false)
  assert.equal(isDirty(select("paragraph_style[text_align]", [ [ "", false ], [ "center", true ] ], "")), true)
  assert.equal(isDirty(select("paragraph_style[text_align]", [ [ "", false ], [ "left", false ] ], "")), false, "none marked: the first option")
})

// Idiomorph asks about an input's `value` twice (morphAttributes, then
// syncInputValue); the first answer rewrites the attribute isDirty reads.
test("LocalValueKeeper decides once per element, before its attributes change", () => {
  const keeper = new LocalValueKeeper(() => false)
  const el = input("paragraph_style[font_size]", "12.0", "12.0") // committed "12.0"
  keeper.decide(el)                                                // turbo:before-morph-element
  assert.equal(keeper.keeps(el), false)
  el.setAttribute("value", "12")                                   // morphAttributes: server's "12"
  assert.equal(isDirty(el), true, "the attribute now differs from .value…")
  assert.equal(keeper.keeps(el), false, "…but the decision taken before still lets syncInputValue set .value")
})

test("LocalValueKeeper keeps a dirty or pending control; ignores other elements", () => {
  const pending = new Set([ "tracking" ])
  const keeper = new LocalValueKeeper((field) => pending.has(field))
  const typing = input("paragraph_style[font_size]", "10", "15")
  const saving = input("paragraph_style[tracking]", "1", "1")
  const other = input("preview_mode", "single", "x")
  for (const el of [ typing, saving, other ]) keeper.decide(el)
  assert.equal(keeper.keeps(typing), true)
  assert.equal(keeper.keeps(saving), true)
  assert.equal(keeper.keeps(other), false)
  assert.equal(keeper.keeps(input("paragraph_style[leading]", "1", "2")), false, "no decision: allow")
})

test("LocalValueKeeper re-decides on the next morph", () => {
  const pending = new Set([ "font_size" ])
  const keeper = new LocalValueKeeper((field) => pending.has(field))
  const el = input("paragraph_style[font_size]", "12", "12")
  keeper.decide(el)
  assert.equal(keeper.keeps(el), true)
  pending.clear()
  keeper.decide(el)
  assert.equal(keeper.keeps(el), false)
})

// A parsed fragment stand-in: turbo-stream elements with a target and remove().
function fragment(targets) {
  const streams = targets.map((target) => ({ target, getAttribute: (n) => n === "target" ? target : null,
                                             remove() { streams.splice(streams.indexOf(this), 1) } }))
  return { streams, querySelectorAll: (sel) => sel === "turbo-stream" ? [ ...streams ] : [] }
}

test("dropStreamsFor removes only the streams aimed at the target", () => {
  const f = fragment([ PANEL_TARGET, "preview_frame" ])
  assert.equal(dropStreamsFor(f, PANEL_TARGET), 1)
  assert.deepEqual(f.streams.map((s) => s.target), [ "preview_frame" ])
  assert.equal(dropStreamsFor(fragment([ "preview_frame" ]), PANEL_TARGET), 0)
  assert.equal(PANEL_TARGET, "style-panel-content")
})
