// Morph rules for the paragraph style panel and the Page section (pure: no
// document/window; node-tested with stand-in elements). design--style-autosave
// uses them to keep what a save's morph must not overwrite, and to drop a late
// response's panel stream once the panel it was meant for is gone.

// The default field prefix and morph target (the style panel's: the id
// StylePanelContent renders and the server's panel stream targets).
export const FIELD_PREFIX = "paragraph_style"
export const PANEL_TARGET = "style-panel-content"
// The ▾ menu (design--dropdown shows and hides it with the `hidden` class) and
// the Page section's Left/Right link toggle.
export const MENU = "[data-design--dropdown-target='menu']"
export const MARGIN_LINK = "[data-margin-link]"

// A name → field function for controls named <prefix>[<field>]
// ("paragraph_style[font_size]" → "font_size"); anything else → null.
export function fieldMatcher(prefix = FIELD_PREFIX) {
  const pattern = new RegExp(`^${escapeRegExp(prefix)}\\[([a-z_]+)\\]$`)
  return (name) => {
    const match = pattern.exec(name ?? "")
    return match ? match[1] : null
  }
}

export const fieldFromName = fieldMatcher()

function escapeRegExp(text) { return String(text).replace(/[.*+?^${}()|[\]\\]/g, "\\$&") }

// Attributes a save's morph leaves as the user set them: a <details>' open
// state, the ▾ menu's class (the server renders it closed) and the margin
// link's aria-pressed (client-side state). Values are LocalValueKeeper's job.
export function keepsUserAttribute(el, attributeName) {
  if (el?.tagName === "DETAILS" && attributeName === "open") return true
  if (attributeName === "class" && el?.matches?.(MENU)) return true
  if (attributeName === "aria-pressed" && el?.matches?.(MARGIN_LINK)) return true
  return false
}

// Keep a control's local value through a morph while its save is unanswered,
// or while it is dirty (its value differs from its committed attributes:
// typing, or a scrub-drag, which never focuses the input).
export function keepsLocalValue({ pending, dirty }) {
  return pending || dirty
}

// The control's value differs from its committed state: the `value`
// attribute, or a select's option[selected] (the first option when none is).
export function isDirty(control) {
  if (control.tagName === "SELECT") {
    const marked = control.querySelector("option[selected]") ?? control.options[0]
    return (marked?.value ?? "") !== control.value
  }
  return (control.getAttribute("value") ?? "") !== control.value
}

// Idiomorph asks about an input's `value` twice per morph — morphAttributes,
// then syncInputValue — and the first answer rewrites the attribute isDirty
// reads, so asking isDirty each time would make the second call cancel the
// update the first allowed. Decide once per element, on turbo:before-morph-
// element (it fires before the element's attributes), and answer every
// turbo:before-morph-attribute for that element from the decision.
export class LocalValueKeeper {
  // fieldOf: the panel's name matcher (fieldMatcher(prefix)).
  constructor(isPending, fieldOf = fieldFromName) {
    this.isPending = isPending
    this.fieldOf = fieldOf
    this.decisions = new WeakMap()
  }

  // turbo:before-morph-element: only the panel's named controls.
  decide(el) {
    const field = this.fieldOf(el?.name)
    if (!field) return
    this.decisions.set(el, keepsLocalValue({ pending: this.isPending(field), dirty: isDirty(el) }))
  }

  keeps(control) { return this.decisions.get(control) === true }
}

// Remove the <turbo-stream target="…"> elements aimed at `target` from a
// parsed fragment (a <template>'s content); returns how many were removed.
export function dropStreamsFor(fragment, target) {
  const streams = [ ...fragment.querySelectorAll("turbo-stream") ].filter((s) => s.getAttribute("target") === target)
  streams.forEach((s) => s.remove())
  return streams.length
}
