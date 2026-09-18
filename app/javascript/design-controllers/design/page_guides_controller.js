import { Controller } from "@hotwired/stimulus"
import { guideRects } from "design-controllers/design/page_guides"

// One preview page's guides — margins (magenta), binding strip (shaded, print
// mode only), columns (violet) — drawn into the layer target on connect (every
// preview render replaces the pages). The geometry (pt) comes from the server
// (Preview#guide_geometry); the layer's classes (Ruby) hide it while the
// preview section has data-guides="off". Inline styles only (Tailwind scans Ruby).
const MAGENTA = "#d946ef"
const BINDING_FILL = "rgba(217, 70, 239, 0.12)"
const VIOLET = "#8b5cf6"

export default class extends Controller {
  static targets = ["layer"]
  static values = { geometry: Object }

  connect() { this.draw() }

  draw() {
    const rects = guideRects(this.geometryValue)
    const boxes = []
    if (rects) {
      if (rects.binding) boxes.push(box(rects.binding, { background: BINDING_FILL }))
      for (const column of rects.columns) boxes.push(box(column, { outline: `1px solid ${VIOLET}`, outlineOffset: "-1px" }))
      boxes.push(box(rects.margin, { outline: `1px solid ${MAGENTA}`, outlineOffset: "-1px" }))
    }
    this.layerTarget.replaceChildren(...boxes)
  }
}

function box(rect, style) {
  const el = document.createElement("div")
  Object.assign(el.style, { position: "absolute", boxSizing: "border-box", left: `${rect.left}%`, top: `${rect.top}%`,
                            width: `${rect.width}%`, height: `${rect.height}%` }, style)
  return el
}
