import { Controller } from "@hotwired/stimulus"

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

      if (response.ok) {
        const html = await response.text()
        window.Turbo.renderStreamMessage(html)
        this._showStatus("Saved")
      } else {
        this._showStatus("Error")
      }
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

  _showStatus(text) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = text
    this.statusTarget.classList.remove("hidden")
    if (text === "Saved") {
      setTimeout(() => this.statusTarget.classList.add("hidden"), 1500)
    }
  }
}
