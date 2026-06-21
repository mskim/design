import { Controller } from "@hotwired/stimulus"

// Read-only lightbox carousel over the doc-type preview thumbnails.
// Each item target carries data-url (full preview JPG) and data-label.
export default class extends Controller {
  static targets = ["item"]

  connect() {
    this.onKey = this.onKey.bind(this)
  }

  disconnect() {
    this.close()
  }

  open(event) {
    this.index = Number(event.currentTarget.dataset.index || 0)
    this.render()
    document.addEventListener("keydown", this.onKey)
  }

  render() {
    if (!this.overlay) this.buildOverlay()
    const item = this.itemTargets[this.index]
    if (!item) return
    this.image.src = item.dataset.url
    this.image.alt = item.dataset.label || ""
    this.caption.textContent = item.dataset.label || ""
  }

  next() { this.index = (this.index + 1) % this.itemTargets.length; this.render() }
  prev() { this.index = (this.index - 1 + this.itemTargets.length) % this.itemTargets.length; this.render() }

  onKey(event) {
    if (event.key === "Escape") this.close()
    else if (event.key === "ArrowRight") this.next()
    else if (event.key === "ArrowLeft") this.prev()
  }

  close() {
    document.removeEventListener("keydown", this.onKey)
    if (this.overlay) { this.overlay.remove(); this.overlay = null }
  }

  buildOverlay() {
    const overlay = document.createElement("div")
    overlay.className = "preview-gallery-overlay"
    overlay.style.cssText = "position:fixed;inset:0;z-index:1000;background:rgba(0,0,0,.8);display:flex;flex-direction:column;align-items:center;justify-content:center;gap:12px;padding:24px;"
    overlay.addEventListener("click", (e) => { if (e.target === overlay) this.close() })

    this.image = document.createElement("img")
    this.image.style.cssText = "max-height:80vh;max-width:80vw;object-fit:contain;background:#fff;box-shadow:0 4px 24px rgba(0,0,0,.4);"

    this.caption = document.createElement("div")
    this.caption.style.cssText = "color:#fff;font-size:14px;"

    const nav = document.createElement("div")
    nav.style.cssText = "display:flex;gap:16px;"
    const prev = this.navButton("‹", () => this.prev())
    const nextBtn = this.navButton("›", () => this.next())
    const closeBtn = this.navButton("✕", () => this.close())
    nav.append(prev, closeBtn, nextBtn)

    overlay.append(this.image, this.caption, nav)
    document.body.appendChild(overlay)
    this.overlay = overlay
  }

  navButton(text, handler) {
    const b = document.createElement("button")
    b.type = "button"
    b.textContent = text
    b.style.cssText = "background:#fff;border:none;border-radius:6px;width:40px;height:40px;font-size:20px;cursor:pointer;"
    b.addEventListener("click", handler)
    return b
  }
}
