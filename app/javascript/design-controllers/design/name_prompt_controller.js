import { Controller } from "@hotwired/stimulus"

// Prompts for a name before submitting a form (clone-with-new-name, rename).
// Writes the entered value into the target field; cancelling or an empty
// value aborts the submit so the form never posts a blank/unchanged name.
export default class extends Controller {
  static targets = ["field"]

  confirm(event) {
    const label = this.element.dataset.promptLabel || "Name"
    const current = this.hasFieldTarget ? this.fieldTarget.value : ""
    const value = window.prompt(label, current)

    if (value === null || value.trim() === "") {
      event.preventDefault()
      return
    }

    if (this.hasFieldTarget) this.fieldTarget.value = value.trim()
  }
}
