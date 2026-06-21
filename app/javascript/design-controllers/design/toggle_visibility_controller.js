import { Controller } from "@hotwired/stimulus"

// Toggles visibility of a content target.
// When wired to a checkbox's change event: shows content when checked, hides when unchecked.
// When wired to any other element (button, link): flips the hidden state.
export default class extends Controller {
  static targets = ["content"]

  toggle(event) {
    if (event?.target?.type === "checkbox") {
      this.contentTarget.classList.toggle("hidden", !event.target.checked)
    } else {
      this.contentTarget.classList.toggle("hidden")
    }
  }
}
