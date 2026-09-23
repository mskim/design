require "test_helper"

class Design::PreviewGuidesTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "PG #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "chapter", column_count: 2, gutter: 12)
  end

  def render(dd = @dd, print_mode: false, count: 2)
    pages = (1..count).map { |i| { jpg_url: "/p/#{i}.jpg", overlay_data: [] } }
    Nokogiri::HTML.fragment(Design::Views::DocumentDesigns::Preview.new(
      document_design: dd, paper_size: @ps, pages: pages, page_width: 432.0, page_height: 648.0, print_mode: print_mode).call)
  end

  def geometry(doc, i) = JSON.parse(doc.css("[data-controller~='design--page-guides']")[i]["data-design--page-guides-geometry-value"])
  def mm_pt(v) = (v * Design::PaperSize::MM2PT).to_f

  test "each page carries its guide geometry in pt, with its parity" do
    doc = render
    g1, g2 = geometry(doc, 0), geometry(doc, 1)
    assert_equal %w[odd even], [ g1["parity"], g2["parity"] ]
    assert_equal "columns", g1["kind"]
    assert_in_delta 432.0, g1["width"], 0.001
    assert_in_delta mm_pt(@ps.left_margin_mm), g1["left"], 0.01
    assert_in_delta mm_pt(@ps.top_margin_mm), g1["top"], 0.01
    assert_in_delta mm_pt(@ps.bottom_margin_mm), g1["bottom"], 0.01
    assert_in_delta mm_pt(@ps.right_margin_mm), g1["right"], 0.01
    assert_in_delta 648.0, g1["height"], 0.001
    assert_equal 0.0, g1["binding"], "not in print mode"
    assert_equal 2, g1["columnCount"]
    assert_in_delta 12.0, g1["gutter"], 0.001
    layer = doc.at_css("[data-design--page-guides-target='layer']")
    assert_includes layer["class"].split, "group-data-[guides=off]/preview:hidden"
    assert_includes layer["class"].split, "pointer-events-none"
  end

  test "each page box redraws its guides after a morph" do
    boxes = render.css("[data-controller~='design--page-guides']")
    assert_equal 2, boxes.size
    boxes.each { |b| assert_includes b["data-action"].to_s.split, "turbo:morph-element->design--page-guides#draw" }
  end

  test "print mode puts the binding (pt) into every page's geometry" do
    assert_in_delta mm_pt(@ps.binding_margin_mm), geometry(render(print_mode: true), 1)["binding"], 0.01
  end

  test "kinds: poem columns, title page margins only, covers and wings nothing" do
    assert_equal "columns", geometry(render(@ps.document_designs.create!(doc_type: "poem")), 0)["kind"]
    assert_equal "margins", geometry(render(@ps.document_designs.create!(doc_type: "title_page")), 0)["kind"]
    %w[front_page front_wing document_cover].each do |t|
      doc = render(@ps.document_designs.create!(doc_type: t))
      assert_nil doc.at_css("[data-controller~='design--page-guides']"), t
      assert_nil doc.at_css("[data-design--page-guides-target='layer']"), t
    end
  end
  test "copyright carries the grid and the effective box, in cells" do
    dd = @ps.document_designs.create!(doc_type: "copyright")
    g = geometry(render(dd), 0)
    assert_equal "grid", g["kind"]
    assert_equal({ "columns" => 6, "rows" => 12 }, g["grid"])
    assert_equal({ "x" => 0.0, "y" => 6.0, "w" => 4.0, "h" => 6.0 }, g["box"], "the 7 / 4 / 6 default")
    dd.update!(text_box_anchor_position: 3, text_box_grid_width: 2, text_box_grid_height: 4)
    assert_equal({ "x" => 4.0, "y" => 0.0, "w" => 2.0, "h" => 4.0 }, geometry(render(dd), 0)["box"])
  end

  # Taking the binding off narrows the content rect, which can turn a nearly
  # square, slightly wide page upright — against SCREEN mode. It never differs
  # between an odd page and an even one: the binding comes off both and only
  # changes sides (Context#page_margins), so the grid is the same on every page
  # and only its origin moves, which page_guides.js works out from the parity.
  test "print mode measures the grid against the bound content rect" do
    ps = @theme.paper_sizes.create!(size_name: "가로", width_mm: 216, height_mm: 210)
    ps.update_columns(left_margin_mm: 10, right_margin_mm: 10, top_margin_mm: 10, bottom_margin_mm: 10,
                      binding_margin_mm: 20)
    dd = ps.document_designs.create!(doc_type: "copyright")
    # Screen: 196 x 190 mm — wider than tall, so 12 x 6. Print: 176 x 190 — upright, so 6 x 12.
    # This size isn't @ps, so the file's `render` helper can't be used.
    preview = ->(print_mode) do
      Nokogiri::HTML.fragment(Design::Views::DocumentDesigns::Preview.new(
        document_design: dd, paper_size: ps, pages: [ { jpg_url: "/p.jpg", overlay_data: [] } ],
        page_width: ps.width_pt, page_height: ps.height_pt, print_mode: print_mode).call)
    end
    assert_equal({ "columns" => 12, "rows" => 6 }, geometry(preview.(false), 0)["grid"])
    assert_equal({ "columns" => 6, "rows" => 12 }, geometry(preview.(true), 0)["grid"])
  end

  test "the grid and the box are the same on an odd and an even page; only the parity differs" do
    dd = @ps.document_designs.create!(doc_type: "copyright", text_box_anchor_position: 3, text_box_grid_width: 2)
    doc = render(dd, print_mode: true, count: 2)
    odd, even = geometry(doc, 0), geometry(doc, 1)
    assert_equal %w[odd even], [ odd["parity"], even["parity"] ]
    assert_equal odd["grid"], even["grid"], "the binding narrows both parities alike"
    assert_equal odd["box"], even["box"]
    assert_in_delta mm_pt(@ps.binding_margin_mm), odd["binding"], 0.01, "the shift itself is page_guides.js's job"
  end

  test "no other doc type gets a grid" do
    %w[chapter poem title_page toc].each do |doc_type|
      # chapter is already there from setup: doc_type is unique per paper size.
      dd = @ps.document_designs.find_by(doc_type: doc_type) || @ps.document_designs.create!(doc_type: doc_type)
      g = geometry(render(dd), 0)
      assert_nil g["grid"], doc_type
      assert_nil g["box"], doc_type
    end
  end

end
