import { Controller } from "@hotwired/stimulus"

// Toggles a dropdown menu; closes on outside click. Ported from book_design.
export default class extends Controller {
  static targets = ["menu"]

  toggle() {
    this.menuTarget.classList.toggle("hidden")
  }

  connect() {
    this.outsideClickHandler = (event) => {
      if (!this.element.contains(event.target)) {
        this.menuTarget.classList.add("hidden")
      }
    }
    document.addEventListener("click", this.outsideClickHandler)
  }

  disconnect() {
    document.removeEventListener("click", this.outsideClickHandler)
  }
}
