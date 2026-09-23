import { test } from "node:test"
import assert from "node:assert/strict"
import { GRID_PORTRAIT, GRID_LANDSCAPE, MIN_CELLS, gridFor, anchorCell, cellRect, dragSize, pointerCells }
  from "../../app/javascript/design-controllers/design/cell_grid.js"

const P = GRID_PORTRAIT // 6 x 12

test("the grid follows the content rect's shape, like DocLayout::Grid", () => {
  assert.deepEqual(gridFor(300, 500), GRID_PORTRAIT)
  assert.deepEqual(gridFor(500, 300), GRID_LANDSCAPE)
  assert.deepEqual(gridFor(400, 400), GRID_LANDSCAPE, "square counts as landscape (width >= height)")
  assert.deepEqual(GRID_PORTRAIT, { columns: 6, rows: 12 })
  assert.deepEqual(GRID_LANDSCAPE, { columns: 12, rows: 6 })
})

// The same nine cases the Ruby twin (DocumentDesign.anchor_cell) asserts.
test("anchorCell places a box at each anchor in reading order", () => {
  assert.deepEqual(anchorCell(P, 1, 2, 3), { x: 0, y: 0, w: 2, h: 3 })
  assert.deepEqual(anchorCell(P, 2, 2, 3), { x: 2, y: 0, w: 2, h: 3 })
  assert.deepEqual(anchorCell(P, 3, 2, 3), { x: 4, y: 0, w: 2, h: 3 })
  assert.deepEqual(anchorCell(P, 4, 2, 3), { x: 0, y: 4.5, w: 2, h: 3 })
  assert.deepEqual(anchorCell(P, 5, 2, 3), { x: 2, y: 4.5, w: 2, h: 3 })
  assert.deepEqual(anchorCell(P, 6, 2, 3), { x: 4, y: 4.5, w: 2, h: 3 })
  assert.deepEqual(anchorCell(P, 7, 2, 3), { x: 0, y: 9, w: 2, h: 3 })
  assert.deepEqual(anchorCell(P, 8, 2, 3), { x: 2, y: 9, w: 2, h: 3 })
  assert.deepEqual(anchorCell(P, 9, 2, 3), { x: 4, y: 9, w: 2, h: 3 })
})

test("anchorCell: centred odd spans land on half cells, and sizes are clamped", () => {
  assert.deepEqual(anchorCell(P, 2, 3, 1), { x: 1.5, y: 0, w: 3, h: 1 })
  assert.deepEqual(anchorCell(P, 5, 40, 40), { x: 0, y: 0, w: 6, h: 12 })
  assert.deepEqual(anchorCell(P, 7, 0, -3), { x: 0, y: 11.5, w: MIN_CELLS, h: MIN_CELLS })
  assert.deepEqual(anchorCell(P, 0, 2, 3), anchorCell(P, 1, 2, 3))
  assert.deepEqual(anchorCell(P, 99, 2, 3), anchorCell(P, 9, 2, 3))
  assert.deepEqual(anchorCell(P, null, 2, 3), anchorCell(P, 1, 2, 3))
})

test("cellRect is the box in percent of the grid", () => {
  assert.deepEqual(cellRect(P, { x: 3, y: 6, w: 3, h: 3 }), { left: 50, top: 50, width: 50, height: 25 })
})

// The free corner is the one opposite the anchor; an edge or centre anchor
// grows symmetrically along its free axis, which is what keeps it anchored.
test("dragSize: a corner anchor measures from its own corner", () => {
  assert.deepEqual(dragSize({ ...P, anchor: 1, pointer: { x: 3.4, y: 5.6 } }), { w: 3, h: 6 })
  assert.deepEqual(dragSize({ ...P, anchor: 9, pointer: { x: 3.4, y: 5.6 } }), { w: 3, h: 6 })
  assert.deepEqual(dragSize({ ...P, anchor: 3, pointer: { x: 4.5, y: 2.5 } }), { w: 2, h: 3 })
  assert.deepEqual(dragSize({ ...P, anchor: 7, pointer: { x: 1.2, y: 8.8 } }), { w: 1, h: 3 })
})

test("dragSize: an edge anchor grows symmetrically along its free axis", () => {
  // Anchor 2 is top-centre: x is centred (span = twice the distance from the
  // middle), y starts at the top.
  assert.deepEqual(dragSize({ ...P, anchor: 2, pointer: { x: 4.5, y: 4.4 } }), { w: 3, h: 4 })
  assert.deepEqual(dragSize({ ...P, anchor: 8, pointer: { x: 1.5, y: 8 } }), { w: 3, h: 4 })
  assert.deepEqual(dragSize({ ...P, anchor: 4, pointer: { x: 2, y: 9 } }), { w: 2, h: 6 })
  assert.deepEqual(dragSize({ ...P, anchor: 6, pointer: { x: 2, y: 3 } }), { w: 4, h: 6 })
})

test("dragSize: the centre grows symmetrically on both axes", () => {
  assert.deepEqual(dragSize({ ...P, anchor: 5, pointer: { x: 4.5, y: 7.5 } }), { w: 3, h: 3 })
  assert.deepEqual(dragSize({ ...P, anchor: 5, pointer: { x: 1.5, y: 4.5 } }), { w: 3, h: 3 },
                   "dragging past the anchor mirrors rather than inverting")
})

test("dragSize snaps to whole cells and never leaves 1..cells", () => {
  assert.deepEqual(dragSize({ ...P, anchor: 1, pointer: { x: 0.1, y: 0.1 } }), { w: 1, h: 1 })
  assert.deepEqual(dragSize({ ...P, anchor: 1, pointer: { x: 99, y: 99 } }), { w: 6, h: 12 })
  assert.deepEqual(dragSize({ ...GRID_LANDSCAPE, anchor: 1, pointer: { x: 11.7, y: 5.6 } }), { w: 12, h: 6 })
})

test("pointerCells maps a pointer inside the sketch to cells, clamped to it", () => {
  const box = { left: 100, top: 200, width: 300, height: 600, ...P }
  assert.deepEqual(pointerCells(box, 250, 500), { x: 3, y: 6 })
  assert.deepEqual(pointerCells(box, 0, 0), { x: 0, y: 0 })
  assert.deepEqual(pointerCells(box, 9999, 9999), { x: 6, y: 12 })
  assert.deepEqual(pointerCells({ ...box, width: 0, height: 0 }, 150, 250), { x: 0, y: 0 },
                   "a sketch with no size (display:none) never divides by zero")
})
