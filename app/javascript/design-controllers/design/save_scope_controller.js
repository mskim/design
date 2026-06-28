import { Controller } from "@hotwired/stimulus"

// Guards the "apply to all document types" save: when the box is checked and at
// least one same-name per-doc_type override would be reset, ask for confirmation.
// Registered ahead of panel-autosave on the form's submit action, so cancelling
// here (preventDefault + stopImmediatePropagation) stops the autosave handler.
export default class extends Controller {
  static targets = ["checkbox"]
  static values = { count: Number, message: String }

  confirmScope(event) {
    if (!this.hasCheckboxTarget || !this.checkboxTarget.checked) return
    if (this.countValue <= 0) return
    if (!window.confirm(this.messageValue)) {
      event.preventDefault()
      event.stopImmediatePropagation()
    }
  }
}
