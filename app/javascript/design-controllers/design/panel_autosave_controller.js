import { Controller } from "@hotwired/stimulus"
import { saveResponseOutcome } from "design-controllers/design/panel_save_response"

export default class extends Controller {
  static targets = ["status"]

  connect() {
    this._timeout = null
    this._saving = false
  }

  disconnect() {
    clearTimeout(this._timeout)
  }

  scheduleUpdate() {
    clearTimeout(this._timeout)
    this._timeout = setTimeout(() => this._autoSave(), 600)
  }

  save(event) {
    event.preventDefault()
    clearTimeout(this._timeout)
    this._autoSave()
  }

  async _autoSave() {
    if (this._saving) return
    this._saving = true
    this._showStatus("Saving...")

    const previewFrame = document.getElementById("preview_frame")
    if (previewFrame) {
      previewFrame.style.opacity = "0.5"
      previewFrame.style.pointerEvents = "none"
    }

    try {
      const formData = new FormData(this.element)
      const token = formData.get("authenticity_token")

      const response = await fetch(this.element.action, {
        method: "POST",
        headers: {
          "Accept": "text/vnd.turbo-stream.html",
          "X-CSRF-Token": token
        },
        body: formData
      })

      // A non-ok response still carries the panel to show (a stale Save's 409,
      // a 422 with validation errors): swap it in, then report "Error".
      const html = await response.text()
      const outcome = saveResponseOutcome({
        ok: response.ok, contentType: response.headers.get("Content-Type"), body: html
      })
      if (outcome.render === "stream") window.Turbo.renderStreamMessage(html)
      else if (outcome.render === "frame") this._replacePanel(html)
      this._showStatus(outcome.status)
    } catch {
      this._showStatus("Error")
    } finally {
      this._saving = false
      const previewFrame = document.getElementById("preview_frame")
      if (previewFrame) {
        previewFrame.style.opacity = "1"
        previewFrame.style.pointerEvents = "auto"
      }
    }
  }

  _replacePanel(html) {
    const fresh = new DOMParser().parseFromString(html, "text/html").getElementById("properties_panel")
    const current = document.getElementById("properties_panel")
    if (fresh && current) current.replaceWith(document.importNode(fresh, true))
  }

  _showStatus(text) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = text
    this.statusTarget.classList.remove("hidden")
    if (text === "Saved") {
      setTimeout(() => this.statusTarget.classList.add("hidden"), 1500)
    }
  }
}
