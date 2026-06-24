import { Controller } from "@hotwired/stimulus"

// Submits the enclosing form when a filter changes. Ported from book_design.
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
