import { Controller } from "@hotwired/stimulus"
import { StyleSaveQueue, fieldFromName, keepsLocalValue } from "design-controllers/design/style_save_queue"

// Autosave for the paragraph style panel (D2b). Each committed field change —
// the `change` a NumberField commit, a select, a ColorField close or a border/
// corner toggle emits — becomes one request; × buttons and the ▾ menu add
// theirs. Requests run one at a time, in order (StyleSaveQueue). Responses are
// turbo streams that morph #style-panel-content (and replace the preview); the
// morph keeps focus, and the handlers below keep what it must not overwrite:
// a value whose save is unanswered, an uncommitted (dirty) value — typing or a
// scrub-drag — an open colour popover, each <details>' open state and the ▾
// menu's open state. When the last request of a burst fails without a stream,
// the preview is reloaded.

// The ▾ menu (design--dropdown shows and hides it with the `hidden` class).
const MENU = "[data-design--dropdown-target='menu']"

export default class extends Controller {
  static targets = ["status"]
  static values = { fieldUrl: String, styleUrl: String, pushUrl: String, previewUrl: String, previewMode: String,
                    savingText: String, savedText: String, errorText: String }

  connect() {
    this.queue = new StyleSaveQueue({ send: (job, opts) => this.send(job, opts), onStatus: (s) => this.showStatus(s) })
  }

  // change (bubbling) on the form. Popover sub-fields have no name and other
  // inputs aren't paragraph_style[<field>]: both ignored.
  fieldChanged(event) {
    const el = event.target
    const field = fieldFromName(el?.name)
    if (!field || el.disabled) return
    markCommitted(el)
    const value = (el.value ?? "").trim()
    this.queue.enqueue(value === ""
      ? { key: field, method: "DELETE", url: this.fieldUrlValue, field }
      : { key: field, method: "PATCH", url: this.fieldUrlValue, field, value })
  }

  // × on a field
  revert(event) {
    const field = event.currentTarget.dataset.field
    if (field) this.queue.enqueue({ key: field, method: "DELETE", url: this.fieldUrlValue, field })
  }

  // ▾ 되돌리기 (N)
  revertStyle(event) {
    closeMenu(event)
    this.queue.enqueue({ key: ":style", method: "DELETE", url: this.styleUrlValue })
  }

  // ▾ 테마에 반영… / 장에 반영… (confirm text carries push_preview's counts).
  // The menu closes whether the confirm is accepted or cancelled.
  pushStyle(event) {
    closeMenu(event)
    const message = event.currentTarget.dataset.confirmMessage
    if (message && !window.confirm(message)) return
    this.queue.enqueue({ key: ":push", method: "POST", url: this.pushUrlValue })
  }

  ignoreSubmit(event) { event.preventDefault() }

  // turbo:before-morph-attribute
  keepLocalState(event) {
    const el = event.target
    const { attributeName } = event.detail
    if (el.tagName === "DETAILS" && attributeName === "open") { event.preventDefault(); return }
    // The server always renders the menu closed; keep a menu the user opened.
    if (attributeName === "class" && el.matches(MENU)) { event.preventDefault(); return }
    if (attributeName !== "value" && attributeName !== "selected") return
    const control = el.tagName === "OPTION" ? el.closest("select") : el
    const field = fieldFromName(control?.name)
    if (!field) return
    // Not focus-based: a scrub-drag changes the value without focusing the input.
    if (keepsLocalValue({ pending: this.queue.isPending(field), dirty: isDirty(control) })) event.preventDefault()
  }

  // turbo:before-morph-element — an open colour row is left alone entirely.
  keepOpenPopover(event) {
    const el = event.target
    if (!(el instanceof Element) || !el.matches("[data-controller~='design--color-row']")) return
    const popover = el.querySelector("[data-design--color-row-target='popover']")
    if (popover && !popover.hidden) event.preventDefault()
  }

  async send(job, { renderPreview }) {
    const body = new FormData()
    if (job.method !== "POST") body.append("_method", job.method)
    if (job.field) body.append("field", job.field)
    if (job.value !== undefined) body.append("value", job.value)
    if (this.previewModeValue) body.append("preview_mode", this.previewModeValue)
    body.append("render_preview", renderPreview ? "1" : "0")
    let response
    try {
      response = await fetch(job.url, {
        method: "POST", body, credentials: "same-origin",
        headers: { Accept: "text/vnd.turbo-stream.html", "X-CSRF-Token": this.csrfToken }
      })
    } catch (error) {
      // Network error on the burst's last request: earlier saves skipped the
      // preview (render_preview=0), so fetch it now.
      if (renderPreview) this.reloadPreview()
      throw error
    }
    const html = await response.text()
    const isStream = (response.headers.get("Content-Type") || "").includes("turbo-stream")
    return {
      ok: response.ok,
      apply: () => {
        if (isStream) window.Turbo?.renderStreamMessage(html)
        // A 400/403/404/500 brings no stream (a 422 carries its own preview).
        else if (renderPreview) this.reloadPreview()
      }
    }
  }

  // Load the preview frame from its GET URL (the panel's preview mode): a
  // stream-replaced frame has no src, so set it; an unchanged src reloads.
  reloadPreview() {
    const frame = document.getElementById("preview_frame")
    if (!frame || !this.previewUrlValue) return
    if (frame.getAttribute("src") === this.previewUrlValue) frame.reload()
    else frame.setAttribute("src", this.previewUrlValue)
  }

  get csrfToken() {
    return this.element.querySelector("input[name='authenticity_token']")?.value ||
           document.querySelector("meta[name='csrf-token']")?.content || ""
  }

  showStatus(status) {
    if (!this.hasStatusTarget) return
    const text = { saving: this.savingTextValue, saved: this.savedTextValue, error: this.errorTextValue }[status]
    this.statusTarget.textContent = text ?? ""
    this.statusTarget.dataset.status = status ?? ""
  }
}

// Close the ▾ menu an item was chosen from (before any confirm; `hidden` is in
// the Ruby markup). keepLocalState keeps the menu's class through a morph, so
// it closes only here, on its toggle, or on an outside click.
function closeMenu(event) {
  event?.currentTarget?.closest(MENU)?.classList.add("hidden")
}

// The control's current state becomes its "server" state (the value/selected
// attributes), so a later morph can tell committed values from uncommitted ones
// (typing, a scrub-drag) — see isDirty.
function markCommitted(el) {
  if (el instanceof HTMLSelectElement) {
    for (const option of el.options) option.toggleAttribute("selected", option.selected)
  } else {
    el.setAttribute("value", el.value)
  }
}

function isDirty(control) {
  if (control instanceof HTMLSelectElement) {
    const marked = control.querySelector("option[selected]") ?? control.options[0]
    return (marked?.value ?? "") !== control.value
  }
  return (control.getAttribute("value") ?? "") !== control.value
}
