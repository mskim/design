import { Controller } from "@hotwired/stimulus"
import { guideRects } from "design-controllers/design/page_guides"

// One preview page's guides — margins (magenta), binding strip (shaded, print
// mode only), columns (violet) — drawn into the layer target whenever the
// geometry value changes (Stimulus also calls geometryValueChanged on
// initialize) and after a morph of the page box (the preview's
// turbo:morph-element action; a morph empties the layer). The geometry (pt)
// comes from the server (Preview#guide_geometry); the layer's classes (Ruby)
// hide it while the preview section has data-guides="off". Inline styles only
// (Tailwind scans Ruby).
const MAGENTA = "#d946ef"
const BINDING_FILL = "rgba(217, 70, 239, 0.12)"
const VIOLET = "#8b5cf6"
const GRID_LINE = "rgba(217, 70, 239, 0.25)"
const BOX = "#0ea5e9"

export default class extends Controller {
  static targets = ["layer"]
  static values = { geometry: Object }

  geometryValueChanged() { this.draw() }

  draw() {
    const rects = guideRects(this.geometryValue)
    const boxes = []
    if (rects) {
      if (rects.binding) boxes.push(box(rects.binding, { background: BINDING_FILL }))
      if (rects.grid) {
        for (const left of rects.grid.vertical) boxes.push(rule({ left: `${left}%`, top: `${rects.grid.top}%`,
                                                                 width: "0", height: `${rects.grid.height}%` }))
        for (const top of rects.grid.horizontal) boxes.push(rule({ left: `${rects.grid.left}%`, top: `${top}%`,
                                                                   width: `${rects.grid.width}%`, height: "0" }))
      }
      if (rects.box) boxes.push(box(rects.box, { outline: `1px solid ${BOX}`, outlineOffset: "-1px" }))
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

// A hairline: a zero-width (or zero-height) element with a border on one side,
// so a 1px line never scales with the page.
function rule(style) {
  const el = document.createElement("div")
  Object.assign(el.style, { position: "absolute", boxSizing: "border-box",
                            borderLeft: style.width === "0" ? `1px solid ${GRID_LINE}` : "",
                            borderTop: style.height === "0" ? `1px solid ${GRID_LINE}` : "" }, style)
  return el
}
