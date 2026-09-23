require "test_helper"

class Design::CellGridTest < ActiveSupport::TestCase
  Sketch = Design::Views::Inputs::CellGrid

  def render(columns: 6, rows: 12, anchor: 7, cell: { x: 0.0, y: 6.0, w: 4.0, h: 6.0 }, **opts)
    Nokogiri::HTML.fragment(Sketch.new(columns: columns, rows: rows, anchor: anchor, cell: cell, **opts).call)
  end

  test "the sketch keeps the grid's aspect and draws the box in percent" do
    doc = render
    grid = doc.at_css("[data-design--cell-grid-target='grid']")
    assert_includes grid["style"], "aspect-ratio: 6 / 12"
    box = doc.at_css("[data-design--cell-grid-target='box']")
    assert_includes box["style"], "left: 0.0%"
    assert_includes box["style"], "top: 50.0%"
    assert_includes box["style"], "width: 66.667%"
    assert_includes box["style"], "height: 50.0%"
  end

  test "the handle sits on the free corner — the one opposite the anchor" do
    { 1 => %w[-right-1 -bottom-1], 3 => %w[-left-1 -bottom-1], 7 => %w[-right-1 -top-1],
      9 => %w[-left-1 -top-1], 5 => %w[-right-1 -bottom-1], 2 => %w[-right-1 -bottom-1] }.each do |anchor, classes|
      handle = render(anchor: anchor).at_css("[data-design--cell-grid-target='handle']")
      assert handle, "anchor #{anchor} must have a handle"
      classes.each { |c| assert_includes handle["class"].split, c, "anchor #{anchor}" }
      assert_includes handle["data-action"], "pointerdown->design--cell-grid#dragStart"
      assert_includes handle["data-action"], "lostpointercapture->design--cell-grid#dragEnd"
    end
  end

  test "a read-only sketch has no handle: draggable false, or disabled" do
    assert_nil render(draggable: false).at_css("[data-design--cell-grid-target='handle']")
    assert_nil render(disabled: true).at_css("[data-design--cell-grid-target='handle']")
    assert_equal "A size sketch", render(draggable: false, hint: "A size sketch").at_css("p").text
    assert_nil render.at_css("p")
  end

  test "a landscape grid turns the sketch around" do
    assert_includes render(columns: 12, rows: 6, cell: { x: 0.0, y: 0.0, w: 6.0, h: 3.0 })
                    .at_css("[data-design--cell-grid-target='grid']")["style"], "aspect-ratio: 12 / 6"
  end
end
