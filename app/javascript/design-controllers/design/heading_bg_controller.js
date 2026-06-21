import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["typeRadio", "colorFields", "imageFields", "gradientFields"]

  typeChanged() {
    const selected = this.typeRadioTargets.find(r => r.checked)?.value || "color"

    this.colorFieldsTarget.classList.toggle("hidden", selected !== "color")
    this.imageFieldsTarget.classList.toggle("hidden", selected !== "image")
    this.gradientFieldsTarget.classList.toggle("hidden", selected !== "gradient")
  }
}
