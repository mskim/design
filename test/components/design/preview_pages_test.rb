require "test_helper"

class Design::PreviewPagesTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "Pv #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "chapter")
  end

  def pages(n)
    (1..n).map { |i| { jpg_url: "/p/#{i}.jpg", overlay_data: [ { type: "paragraph", markup: "body", x: 1, y: 1, width: 5, height: 5 } ] } }
  end

  def render_preview(mode:, count:)
    Nokogiri::HTML.fragment(
      Design::Views::DocumentDesigns::Preview.new(document_design: @dd, paper_size: @ps, pages: pages(count), mode: mode,
                                                  page_width: 432.0, page_height: 648.0).call
    )
  end

  test "scroll mode stacks every page with its own overlay and a page label" do
    doc = render_preview(mode: :scroll, count: 3)
    assert_equal 3, doc.css("turbo-frame#preview_frame img").size
    assert_equal 3, doc.css("turbo-frame#preview_frame svg").size
    assert_equal [ "1 / 3", "2 / 3", "3 / 3" ], doc.css("[data-page-label]").map { |n| n.text.strip }
    assert_equal "/p/2.jpg", doc.css("img")[1]["src"]
  end

  test "single mode renders only page 1 and no label" do
    doc = render_preview(mode: :single, count: 3)
    assert_equal 1, doc.css("img").size
    assert_equal "/p/1.jpg", doc.at_css("img")["src"]
    assert_empty doc.css("[data-page-label]")
  end

  test "legacy jpg_url kwarg still renders one page" do
    doc = Nokogiri::HTML.fragment(
      Design::Views::DocumentDesigns::Preview.new(document_design: @dd, paper_size: @ps, jpg_url: "/one.jpg", overlay_data: []).call
    )
    assert_equal 1, doc.css("img").size
  end
end
