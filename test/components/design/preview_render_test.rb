require "test_helper"

class Design::PreviewRenderTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "PV #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "chapter")
  end

  test "Preview renders frame + img + overlay zone wired to navigate to the style's edit page" do
    html = Design::Views::DocumentDesigns::Preview.new(
      document_design: @dd, paper_size: @ps, jpg_url: "/x.jpg",
      overlay_data: [ { type: "paragraph", markup: "body", x: 10, y: 10, width: 100, height: 20 } ],
      page_width: 432.0, page_height: 648.0,
      style_urls: { "body" => "/design/zzz/edit" }
    ).call
    assert_includes html, "turbo-frame"
    assert_includes html, "/x.jpg"
    assert_includes html, "<svg"
    assert_includes html, "/design/zzz/edit"        # the zone's target url (value)
    assert_includes html, "design--overlay-link"    # navigates via the controller, not an SVG href
    refute_includes html, 'href="/design/zzz/edit"' # no SVG <a href> (Turbo chokes on those)
  end

  test "overlay zone with no matching style_url renders inertly (g, no link) without raising" do
    html = Design::Views::DocumentDesigns::Preview.new(
      document_design: @dd, paper_size: @ps, jpg_url: "/x.jpg",
      overlay_data: [ { type: "paragraph", markup: "unmapped", x: 1, y: 1, width: 5, height: 5 } ],
      page_width: 100.0, page_height: 100.0, style_urls: {}
    ).call
    assert_includes html, "<svg"
    assert_includes html, "<g"        # inert fallback for an unmatched zone
  end

  test "Preview without jpg shows fallback" do
    html = Design::Views::DocumentDesigns::Preview.new(document_design: @dd, paper_size: @ps).call
    assert_includes html, "turbo-frame"
  end

  test "PreviewError renders message in a frame" do
    html = Design::Views::DocumentDesigns::PreviewError.new(error: "boom").call
    assert_includes html, "turbo-frame"
    assert_includes html, "boom"
  end
end
