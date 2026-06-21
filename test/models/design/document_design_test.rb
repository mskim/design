require "test_helper"

class Design::DocumentDesignTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "T #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "chapter")
  end

  test "exposes the new superset columns with defaults" do
    assert_equal "single_any_side", @dd.cover_type
    assert_equal false, @dd.has_document_cover
    assert_respond_to @dd, :footnote_char
    assert_respond_to @dd, :heading_bg_gradient_start
    assert_respond_to @dd, :page_type
  end

  test "ported constants and helpers are available" do
    assert_includes Design::DocumentDesign::SINGLE_PAGE_TYPES, "title_page"
    assert_includes Design::DocumentDesign::COVER_TYPES, "spread"
    assert_equal %w[title], Design::DocumentDesign.default_elements_for("chapter")
    assert_equal false, @dd.single_page?
  end

  test "heading_bg_image attaches" do
    @dd.heading_bg_image.attach(io: StringIO.new("img"), filename: "bg.png", content_type: "image/png")
    assert @dd.heading_bg_image.attached?
  end

  test "cover_type validation only fires when has_document_cover" do
    @dd.update!(cover_type: "nonsense")            # allowed: has_document_cover false
    @dd.has_document_cover = true
    @dd.cover_type = "bogus"
    assert_not @dd.valid?
    @dd.cover_type = "spread"
    assert @dd.valid?
  end

  test "doc_type is NOT strictly validated (existing data not rejected)" do
    assert @ps.document_designs.build(doc_type: "weird_legacy_type").valid?
  end

  test "populate_default_heading_elements creates elements for the doc_type" do
    cover = @ps.document_designs.create!(doc_type: "inside_cover")
    cover.populate_default_heading_elements
    assert_equal %w[title subtitle author publisher], cover.heading_elements.order(:position).pluck(:element_type)
  end
end
