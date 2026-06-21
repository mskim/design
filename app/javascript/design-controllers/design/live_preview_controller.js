import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { previewUrl: String }

  connect() {
    this._timeout = null
    this._loading = false
  }

  disconnect() {
    clearTimeout(this._timeout)
  }

  scheduleUpdate() {
    clearTimeout(this._timeout)
    this._timeout = setTimeout(() => this._fetchPreview(), 800)
  }

  async _fetchPreview() {
    if (this._loading) return
    this._loading = true

    const previewFrame = document.getElementById("preview_frame")
    if (previewFrame) {
      previewFrame.style.opacity = "0.5"
      previewFrame.style.pointerEvents = "none"
    }

    try {
      const form = this.element.tagName === "FORM" ? this.element : this.element.querySelector("form")
      if (!form) return
      const formData = new FormData(form)
      formData.delete("_method")
      const token = formData.get("authenticity_token")

      const response = await fetch(this.previewUrlValue, {
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
      }
    } finally {
      this._loading = false
      const previewFrame = document.getElementById("preview_frame")
      if (previewFrame) {
        previewFrame.style.opacity = "1"
        previewFrame.style.pointerEvents = "auto"
      }
    }
  }
}
