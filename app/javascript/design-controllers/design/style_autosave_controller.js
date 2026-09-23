import { Controller } from "@hotwired/stimulus"
import { StyleSaveQueue } from "design-controllers/design/style_save_queue"
import { fieldMatcher, LocalValueKeeper, dropStreamsFor, keepsUserAttribute, PANEL_TARGET, FIELD_PREFIX, MENU, MARGIN_LINK }
  from "design-controllers/design/style_panel_morph"
import { saveJobs, partnerInput, jointFields, valuesFor, groupJobs, mirrorTargets } from "design-controllers/design/field_save_jobs"

// Autosave for the paragraph style panel (D2b) and the Layout tab's Page
// section (D3: margins, binding, body lines, columns). Each committed field
// change — the `change` a NumberField commit, a select, a ColorField close or
// a border/corner toggle emits — becomes one request (field_save_jobs.js);
// × buttons and the ▾ menu add theirs. Requests run one at a time, in order
// (StyleSaveQueue). Responses are turbo streams that morph the panel target
// (#style-panel-content or #page-section-content) and replace the preview;
// the morph keeps focus, and the handlers below keep what it must not
// overwrite: a value whose save is unanswered, an uncommitted (dirty) value —
// typing or a scrub-drag — an open colour popover, each <details>' open
// state, the ▾ menu's open state and the 🔗 margin link's pressed state.
// A control marked `data-joint-with` (the Object section's two cell sizes) is
// saved together with the fields it names, in one request.
// A 🔗 border/corner row (the style panel, D5) writes or reverts its whole
// group in one request; its toggle's state and its box's `data-linked`
// survive morphs.
// Whether a control keeps its value is decided once per morphed element
// (LocalValueKeeper). When the last request of a burst fails without a
// stream, the preview is reloaded. Once the panel is gone (the frame moved
// to another style), waiting saves are dropped and a late response renders
// only its preview stream, never the panel stream, which would land in the
// next panel with the same id.
//
// Configured by data values: `field-prefix` (controls named <prefix>[<field>];
// `paragraph_style` by default, `page` for the Page section), `panel-target`
// (the morphed element's id; `style-panel-content` by default,
// `page-section-content` for the Page section) and `required-fields` (never
// reverted: emptying one PATCHes "" — the Page section's column count and
// gutter). A `[data-margin-link]` toggle inside the element links the Left
// and Right margins: a value sets both in one request, a revert reverts both.

export default class extends Controller {
  static targets = ["status"]
  static values = { fieldUrl: String, styleUrl: String, pushUrl: String, previewUrl: String, previewMode: String,
                    fieldPrefix: { type: String, default: FIELD_PREFIX },
                    panelTarget: { type: String, default: PANEL_TARGET },
                    requiredFields: Array,
                    savingText: String, savedText: String, errorText: String }

  connect() {
    this.disconnected = false
    this.queue = new StyleSaveQueue({ send: (job, opts) => this.send(job, opts), onStatus: (s) => this.showStatus(s) })
    this.fieldOf = fieldMatcher(this.fieldPrefixValue)
    this.keeper = new LocalValueKeeper((field) => this.queue.isPending(field), this.fieldOf)
    // Listened to here (not a data-action) so it runs for every morphed element.
    this.decideLocalValue = (event) => this.keeper.decide(event.target)
    this.element.addEventListener("turbo:before-morph-element", this.decideLocalValue)
    // Unsent or unanswered saves would be lost by leaving the page.
    this.guardUnload = (event) => {
      if (!this.queue.busy) return
      event.preventDefault()
      event.returnValue = ""
    }
    window.addEventListener("beforeunload", this.guardUnload)
  }

  // The panel is gone: saves still waiting are dropped (the user left it);
  // the one in flight completes and renders only its preview stream.
  disconnect() {
    this.disconnected = true
    this.queue.stop()
    this.element.removeEventListener("turbo:before-morph-element", this.decideLocalValue)
    window.removeEventListener("beforeunload", this.guardUnload)
  }

  // change (bubbling). Popover sub-fields have no name and other inputs don't
  // match the prefix: both ignored.
  fieldChanged(event) {
    const el = event.target
    const row = el?.closest?.("[data-link-fields]")
    if (row && !this.fieldOf(el?.name)) return this.groupChanged(el, row)
    const field = this.fieldOf(el?.name)
    if (!field || el.disabled) return
    markCommitted(el)
    const value = (el.value ?? "").trim()
    const linked = this.linked
    if (linked && value !== "") this.mirrorPartner(field, value)
    this.enqueueAll(saveJobs({ field, value, url: this.fieldUrlValue, linked, required: this.requiredFieldsValue,
                               joint: this.jointValues(el, field) }))
  }

  // × on a field (with the link on, × on Left or Right reverts both).
  revert(event) {
    const field = event.currentTarget.dataset.field
    if (field) {
      this.enqueueAll(saveJobs({ field, value: "", url: this.fieldUrlValue, linked: this.linked,
                                 required: this.requiredFieldsValue }))
    }
  }

  // 🔗 between Left and Right, or on a border/corner box (flipping the box's
  // data-linked too): client-side state (kept through morphs by
  // keepsUserAttribute); the server renders it pressed when the values match.
  toggleLink(event) {
    const button = event.currentTarget
    const pressed = button.getAttribute("aria-pressed") !== "true"
    button.setAttribute("aria-pressed", String(pressed))
    const box = button.closest("[data-link-box]")
    if (box) box.dataset.linked = String(pressed)
  }

  get linked() { return this.element.querySelector(MARGIN_LINK)?.getAttribute("aria-pressed") === "true" }

  // The linked partner shows the committed value at once; its save is part of
  // the pair's request, so the queue reports it pending until the answer.
  mirrorPartner(field, value) {
    const input = partnerInput(this.element.querySelectorAll("[name]"), this.fieldOf, field)
    if (!input || input.value === value) return
    input.value = value
    markCommitted(input)
  }

  // A 🔗 row's control (named paragraph_style_link[…], never a field): its
  // value goes into the group's split controls at once and is saved as one
  // request; emptied, the whole group reverts.
  groupChanged(el, row) {
    if (el.disabled) return
    markCommitted(el)
    const value = (el.value ?? "").trim()
    const fields = row.dataset.linkFields.split(/\s+/).filter(Boolean)
    if (value !== "") {
      for (const input of mirrorTargets(this.element.querySelectorAll("[name]"), this.fieldOf, fields, value)) {
        input.value = value
        markCommitted(input)
      }
    }
    this.enqueueAll(groupJobs({ group: row.dataset.linkGroup, fields, value, url: this.fieldUrlValue }))
  }

  // × on a 🔗 row: the group's four fields back to inherit, in one request.
  revertGroup(event) {
    const row = event.currentTarget.closest("[data-link-fields]")
    if (!row) return
    const fields = row.dataset.linkFields.split(/\s+/).filter(Boolean)
    this.enqueueAll(groupJobs({ group: row.dataset.linkGroup, fields, value: "", url: this.fieldUrlValue }))
  }

  // A control Ruby marked data-joint-with is written together with the fields
  // it names (the Object section's two cell sizes), so the set is validated as
  // a whole. The values come off this section's own controls.
  jointValues(el, field) {
    const fields = jointFields(el.dataset, field)
    return fields && valuesFor(this.element.querySelectorAll("[name]"), this.fieldOf, fields)
  }

  enqueueAll(jobs) { jobs.forEach((job) => this.queue.enqueue(job)) }

  // ▾ 되돌리기 (N) — confirmed when the button carries a confirm message.
  revertStyle(event) {
    closeMenu(event)
    const message = event.currentTarget.dataset.confirmMessage
    if (message && !window.confirm(message)) return
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

  // turbo:before-morph-attribute (value/selected: from the decision decideLocalValue
  // took on turbo:before-morph-element, before this element's attributes changed).
  keepLocalState(event) {
    const el = event.target
    const { attributeName } = event.detail
    // <details>' open, the ▾ menu the user opened, the margin link's state.
    if (keepsUserAttribute(el, attributeName)) { event.preventDefault(); return }
    if (attributeName !== "value" && attributeName !== "selected") return
    const control = el.tagName === "OPTION" ? el.closest("select") : el
    // Not focus-based: a scrub-drag changes the value without focusing the input.
    if (control && this.keeper.keeps(control)) event.preventDefault()
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
    if (job.values) for (const [ f, v ] of Object.entries(job.values)) body.append(`values[${f}]`, v)
    if (job.method === "DELETE" && job.fields) for (const f of job.fields) body.append("fields[]", f)
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
    let html
    try {
      html = await response.text()
    } catch (error) {
      if (renderPreview) this.reloadPreview()
      throw error
    }
    // A redirect (e.g. to sign-in) or an HTML page is no save, even with a 200.
    const isStream = !response.redirected && (response.headers.get("Content-Type") || "").includes("turbo-stream")
    return {
      ok: response.ok && isStream,
      apply: () => {
        if (isStream) this.renderStreams(html)
        // A 400/403/404/500 or a redirect brings no stream (a 422 carries its own preview).
        else if (renderPreview) this.reloadPreview()
      }
    }
  }

  // Throws without Turbo (the queue counts it as a failure). A panel stream
  // is rendered only into this controller's own panel.
  renderStreams(html) {
    if (!window.Turbo) throw new Error("Turbo is not loaded")
    const streams = this.ownsPanel ? html : withoutStreamsFor(html, this.panelTargetValue)
    if (streams.trim() !== "") window.Turbo.renderStreamMessage(streams)
  }

  get ownsPanel() {
    return !this.disconnected && this.element.contains(document.getElementById(this.panelTargetValue))
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

// The stream message without its <turbo-stream target="…"> elements.
function withoutStreamsFor(html, target) {
  const template = document.createElement("template")
  template.innerHTML = html
  dropStreamsFor(template.content, target)
  return template.innerHTML
}
