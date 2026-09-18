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
//   binding, parity: "odd"|"even", columnCount, gutter }.
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
  return {
    margin: box(left, g.top, contentW, contentH),
    binding: binding > 0 ? box(odd ? g.left : g.width - g.right - binding, 0, binding, g.height) : null,
    columns
  }
}
