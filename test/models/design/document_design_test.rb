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

  test "image_opacity defaults to 100 and logo fields persist" do
    theme = Design::Theme.create!(name: "Op #{SecureRandom.hex(3)}", locale: "ko")
    ps = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.create!(doc_type: "front_page")
    assert_equal 100, dd.image_opacity
    dd.update!(image_opacity: 60, logo_width: 30.0, logo_height: 12.0, logo_position: "center", logo_offset: 2.5)
    dd.reload
    assert_equal 60, dd.image_opacity
    assert_equal "center", dd.logo_position
    assert_in_delta 30.0, dd.logo_width.to_f, 0.001
  end

  test "LOGO_POSITIONS are the allowed logo_position values" do
    assert_equal %w[left center right], Design::DocumentDesign::LOGO_POSITIONS
  end

  test "logo_position must be one of LOGO_POSITIONS (nil allowed)" do
    @dd.logo_position = "diagonal"
    assert_not @dd.valid?
    @dd.logo_position = "center"
    assert @dd.valid?
    @dd.logo_position = nil
    assert @dd.valid?
  end

  test "image_opacity must be an integer 0..100 (nil allowed)" do
    @dd.image_opacity = 150
    assert_not @dd.valid?
    @dd.image_opacity = -1
    assert_not @dd.valid?
    @dd.image_opacity = 50
    assert @dd.valid?
    @dd.image_opacity = nil
    assert @dd.valid?
  end
end
