// The Object section's grid arithmetic (pure; node-tested): which cells a box
// covers at an anchor, that box as a percentage of the grid, and the size a
// drag of its free corner gives.
//
// Anchors are reading order — 1 top-left, 5 centre, 9 bottom-right — the same
// as DocLayout::Grid, the HTML renderer's object-position and the anchor grid's
// buttons. DocumentDesign.anchor_cell is the Ruby twin of anchorCell; keep the
// two identical (both are asserted against the same nine cases).

export const GRID_PORTRAIT = { columns: 6, rows: 12 }
export const GRID_LANDSCAPE = { columns: 12, rows: 6 }
// Half a cell is the smallest box the engine will draw (Copyright::MIN_GRID_CELLS).
export const MIN_CELLS = 0.5

// The grid a content rect of this shape gets: 12 x 6 when it is wider than it
// is tall, 6 x 12 otherwise (DocLayout::Grid#initialize).
export function gridFor(width, height) {
  return width >= height ? GRID_LANDSCAPE : GRID_PORTRAIT
}

// The cells a width x height box covers at `anchor`, clamped into the grid:
// { x, y, w, h } with x/y the top-left corner, in cells. A centred span that
// leaves an odd number of cells over sits on a half cell, as the engine's does.
export function anchorCell(grid, anchor, width, height) {
  const position = clamp(Math.trunc(Number(anchor) || 1), 1, 9)
  const w = clamp(Number(width) || 0, MIN_CELLS, grid.columns)
  const h = clamp(Number(height) || 0, MIN_CELLS, grid.rows)
  return {
    x: [ 0, (grid.columns - w) / 2, grid.columns - w ][(position - 1) % 3],
    y: [ 0, (grid.rows - h) / 2, grid.rows - h ][Math.trunc((position - 1) / 3)],
    w: w,
    h: h
  }
}

// A cell box as percentages of the grid, ready for left/top/width/height.
export function cellRect(grid, cell) {
  return { left: 100 * cell.x / grid.columns, top: 100 * cell.y / grid.rows,
           width: 100 * cell.w / grid.columns, height: 100 * cell.h / grid.rows }
}

// The whole-cell size a drag gives, with the anchor's own corner or edge fixed.
// `pointer` is the pointer's position in cells from the grid's top-left
// (pointerCells). A corner anchor measures straight from its corner; an edge or
// centre anchor is centred on its free axis, so the span there is twice the
// distance from the middle — which is why dragging past the middle mirrors
// instead of inverting.
export function dragSize({ columns, rows, anchor, pointer }) {
  const position = clamp(Math.trunc(Number(anchor) || 1), 1, 9)
  return {
    w: span((position - 1) % 3, columns, pointer.x),
    h: span(Math.trunc((position - 1) / 3), rows, pointer.y)
  }
}

// side: 0 = the box starts at the grid's near edge, 2 = it ends at the far one,
// 1 = it is centred.
function span(side, cells, pointer) {
  const raw = side === 0 ? pointer
            : side === 2 ? cells - pointer
            : 2 * Math.abs(pointer - cells / 2)
  return clamp(Math.round(raw), 1, cells)
}

// A pointer position (client coordinates) inside the sketch's rect, in cells.
// `rect` is { left, top, width, height, columns, rows } — plain numbers, so the
// caller reads the rect and this stays pure.
export function pointerCells(rect, clientX, clientY) {
  return {
    x: rect.width > 0 ? clamp((clientX - rect.left) / rect.width * rect.columns, 0, rect.columns) : 0,
    y: rect.height > 0 ? clamp((clientY - rect.top) / rect.height * rect.rows, 0, rect.rows) : 0
  }
}

function clamp(value, min, max) { return Math.min(max, Math.max(min, value)) }
