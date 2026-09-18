import { Controller } from "@hotwired/stimulus"

// Sidebar theme/size selects: every <option> carries the URL to visit in
// data-url (computed server-side), so this controller knows nothing about routes.
export default class extends Controller {
  change(event) {
    const url = event.target.selectedOptions[0]?.dataset.url
    if (url && window.Turbo) {
      window.Turbo.visit(url)
    } else if (url) {
      window.location.assign(url)
    }
  }
}
