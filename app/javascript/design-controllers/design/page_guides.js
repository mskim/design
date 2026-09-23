// Preview guides and the 인쇄용 cookie (pure; node-tested).

export const PRINT_COOKIE = "design_preview_print"
export const GUIDES_KEY = "design.preview.guides"

// The cookie string the 인쇄용 toggle assigns (every preview request reads
// the cookie; kept a year, or cleared).
export function printCookie(on) {
  return `${PRINT_COOKIE}=${on ? "1" : ""}; path=/; max-age=${on ? 31536000 : 0}; SameSite=Lax`
}

// One preview page's guide boxes, in percent of the page: { margin, binding,
// columns } — or null (no guides). g (lengths in pt, from Preview#guide_geometry):
// { kind: "columns"|"margins"|"none", width, height, top, bottom, left, right,
//   binding, parity: "odd"|"even", columnCount, gutter,
//   grid: { columns, rows } | null, box: { x, y, w, h } | null  // cells, for kind "grid"
// }.
// binding is 0 unless the page renders in print mode; like the engine
// (TextBox#margins_for_page) an odd page adds it on the left (the spine side),
// an even page on the right. The binding strip is shaded full height.
export function guideRects(g) {
  if (!g || g.kind === "none" || !(g.width > 0) || !(g.height > 0)) return null
  const odd = g.parity === "odd"
  const binding = Math.max(0, g.binding || 0)
  const gutter = Math.max(0, g.gutter || 0)
  const left = g.left + (odd ? binding : 0)
  const right = g.right + (odd ? 0 : binding)
  const contentW = g.width - left - right
  const contentH = g.height - g.top - g.bottom
  const box = (x, y, w, h) => ({ left: 100 * x / g.width, top: 100 * y / g.height,
                                 width: 100 * Math.max(0, w) / g.width, height: 100 * Math.max(0, h) / g.height })
  const columns = []
  const count = Math.max(1, Math.trunc(g.columnCount || 1))
  if (g.kind === "columns" && count > 1) {
    const colW = (contentW - (count - 1) * gutter) / count
    if (colW > 0) for (let i = 0; i < count; i++) columns.push(box(left + i * (colW + gutter), g.top, colW, contentH))
  }
  // kind "grid" (copyright): the engine's grid over this page's content rect,
  // and the box on it. Both arrive in CELLS from the server, which mirrors
  // DocLayout::Grid; the columns and rows are the same on every page (the
  // binding narrows both parities alike), so all that changes here is the
  // origin — `left` already carries the page's binding shift. Inner cell lines
  // only: the content box is already drawn as the margin guide.
  let grid = null
  let boxRect = null
  if (g.kind === "grid" && g.grid && g.box && g.grid.columns > 0 && g.grid.rows > 0) {
    const cellW = contentW / g.grid.columns
    const cellH = contentH / g.grid.rows
    grid = {
      ...box(left, g.top, contentW, contentH),
      vertical: line(g.grid.columns, (i) => 100 * (left + i * cellW) / g.width),
      horizontal: line(g.grid.rows, (i) => 100 * (g.top + i * cellH) / g.height)
    }
    boxRect = box(left + g.box.x * cellW, g.top + g.box.y * cellH, g.box.w * cellW, g.box.h * cellH)
  }
  return {
    margin: box(left, g.top, contentW, contentH),
    binding: binding > 0 ? box(odd ? g.left : g.width - g.right - binding, 0, binding, g.height) : null,
    columns,
    grid,
    box: boxRect
  }
}

// The inner division lines of `count` equal cells: count - 1 of them.
function line(count, at) {
  const lines = []
  for (let i = 1; i < count; i++) lines.push(at(i))
  return lines
}
