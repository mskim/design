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
    assert_equal 0.0, g1["binding"], "not in print mode"
    assert_equal 2, g1["columnCount"]
    assert_in_delta 12.0, g1["gutter"], 0.001
    layer = doc.at_css("[data-design--page-guides-target='layer']")
    assert_includes layer["class"].split, "group-data-[guides=off]/preview:hidden"
    assert_includes layer["class"].split, "pointer-events-none"
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
end
