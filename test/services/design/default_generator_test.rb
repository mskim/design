require "test_helper"

class Design::DefaultGeneratorTest < ActiveSupport::TestCase
  setup { @theme = Design::Theme.create!(name: "G #{SecureRandom.hex(3)}", locale: "ko") }

  test "creating a paper size fills computed margins + body_line_count" do
    ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    ps.reload
    assert_equal 22.0, ps.left_margin_mm.to_f
    assert_equal 18.0, ps.top_margin_mm.to_f
    assert_equal 28.0, ps.bottom_margin_mm.to_f
    assert_equal 3.0,  ps.binding_margin_mm.to_f
    assert_equal 23,   ps.body_line_count
  end

  test "A4 gets the two-anchor body_line_count (40) and proportional margins" do
    ps = @theme.paper_sizes.create!(size_name: "A4", width_mm: 210, height_mm: 297)
    ps.reload
    assert_equal 30.4, ps.left_margin_mm.to_f
    assert_equal 40,   ps.body_line_count
  end

  test "explicitly set margin is preserved (not clobbered)" do
    ps = @theme.paper_sizes.create!(size_name: "X", width_mm: 152, height_mm: 225, top_margin_mm: 99)
    assert_equal 99.0, ps.reload.top_margin_mm.to_f
    assert_equal 22.0, ps.left_margin_mm.to_f
  end

  test "regenerate is idempotent and honors overridden_fields" do
    ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    ps.update!(left_margin_mm: 12); ps.mark_overridden(:left_margin_mm)
    Design::DefaultGenerator.call(ps); ps.reload
    assert_equal 12.0, ps.left_margin_mm.to_f
    assert_equal 18.0, ps.top_margin_mm.to_f
  end

  # Helper: the gem doesn't seed base styles, so create the ones we assert on.
  def base!(name, size) = @theme.base_paragraph_styles.create!(name: name, font_size: size)

  test "doc_type gets scaled overrides ONLY for its relevant heading styles" do
    base!("title", 24); base!("subtitle", 18); base!("author", 7); base!("body", 9.5)
    ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.create!(doc_type: "title_page")
    sizes = dd.paragraph_styles.index_by(&:name).transform_values { |s| s.font_size&.to_f }
    assert_equal 18.0, sizes["title"]      # 24 × 0.75
    assert_equal 13.5, sizes["subtitle"]   # 18 × 0.75
    assert_equal 6.0,  sizes["author"]     # 7 × 0.75 = 5.25 -> floor 6.0
    assert_nil   sizes["body"]             # body not heading-scaled -> no override created
  end

  test "inside_cover scales only cover_* styles" do
    base!("cover_title", 24); base!("cover_body", 10); base!("title", 24)
    ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.create!(doc_type: "inside_cover")
    names = dd.paragraph_styles.pluck(:name)
    assert_includes names, "cover_title"
    refute_includes names, "cover_body"   # not scaled
    refute_includes names, "title"        # not relevant to inside_cover
  end

  test "heading regenerate honors an overridden font_size" do
    base!("title", 24)
    ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.create!(doc_type: "title_page")
    ov = dd.paragraph_styles.find_by!(name: "title")
    ov.update!(font_size: 99); ov.mark_overridden(:font_size)
    Design::DefaultGenerator.call(ps)
    assert_equal 99.0, ov.reload.font_size.to_f
  end
end
