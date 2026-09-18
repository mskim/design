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

  def size!(**opts) = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225, **opts)
  def resolved(dd, name) = dd.merged_paragraph_styles.find { |s| s.name == name }

  test "chapter gets a sparse scaled font_size row for every heading-scaled style with a base" do
    base!("title", 24); base!("subtitle", 18); base!("author", 7); base!("quote", 12); base!("body", 9.5)
    base!("cover_title", 24); base!("cover_subtitle", 16); base!("cover_author", 10); base!("cover_publisher", 9)
    base!("seneca_title", 12); base!("seneca_author", 9); base!("seneca_publisher", 8)
    ps = size!
    ch = ps.document_designs.create!(doc_type: "chapter")
    rows = ch.paragraph_styles.index_by(&:name)

    assert_equal Design::GenerationRules::HEADING_SCALED_STYLES.sort, rows.keys.sort   # cover_*/seneca_* included; body not
    assert_equal 18.0, rows["title"].font_size.to_f         # 24 × 0.75
    assert_equal 13.5, rows["subtitle"].font_size.to_f      # 18 × 0.75
    assert_equal 6.0,  rows["author"].font_size.to_f        # 7 × 0.75 = 5.25 -> floor 6.0
    assert_equal 18.0, rows["cover_title"].font_size.to_f
    assert_equal 9.0,  rows["seneca_title"].font_size.to_f  # 12 × 0.75
    rows.each_value do |row|
      others = Design::ParagraphStyle::STYLE_FIELDS - %w[font_size]
      assert others.all? { |f| row[f].nil? }, "#{row.name} should be sparse"
      assert_empty Array(row.overridden_fields), "#{row.name} generator value is not a user override"
    end
  end

  test "heading-scaled styles without a theme base get no row" do
    base!("title", 24)
    ch = size!.document_designs.create!(doc_type: "chapter")
    assert_equal %w[title], ch.paragraph_styles.pluck(:name)
  end

  test "non-chapter doc types get no generator rows and resolve scaled sizes through chapter" do
    base!("title", 24); base!("body", 9.5)
    ps = size!
    ps.document_designs.create!(doc_type: "chapter")
    dd = ps.document_designs.create!(doc_type: "title_page")
    assert_empty dd.paragraph_styles
    assert_equal 18.0, resolved(dd, "title").font_size.to_f   # from chapter's scaled row
    assert_equal 9.5,  resolved(dd, "body").font_size.to_f    # not scaled: theme base
  end

  test "inside_cover resolves a scaled cover_title through chapter; cover_body is not scaled" do
    base!("cover_title", 24); base!("cover_body", 10)
    ps = size!
    ch = ps.document_designs.create!(doc_type: "chapter")
    dd = ps.document_designs.create!(doc_type: "inside_cover")
    assert_empty dd.paragraph_styles
    assert_nil ch.paragraph_styles.find_by(name: "cover_body")
    assert_equal 18.0, resolved(dd, "cover_title").font_size.to_f
    assert_equal 10.0, resolved(dd, "cover_body").font_size.to_f
  end

  test "seneca resolves scaled seneca_* styles through chapter" do
    base!("seneca_title", 12); base!("seneca_author", 9)
    ps = @theme.paper_sizes.create!(size_name: "A4", width_mm: 210, height_mm: 297)
    ps.document_designs.create!(doc_type: "chapter")
    dd = ps.document_designs.create!(doc_type: "seneca")
    assert_empty dd.paragraph_styles
    assert_equal 12.0, resolved(dd, "seneca_title").font_size.to_f   # A4 scale × 1.0
    small = size!(size_name: "신국판2")
    small.document_designs.create!(doc_type: "chapter")
    sd = small.document_designs.create!(doc_type: "seneca")
    assert_equal 9.0,  resolved(sd, "seneca_title").font_size.to_f   # 12 × 0.75
    assert_equal 6.8,  resolved(sd, "seneca_author").font_size.to_f  # 9 × 0.75 = 6.75 -> 6.8
  end

  test "heading regenerate honors an overridden font_size on chapter" do
    base!("title", 24)
    ps = size!
    ch = ps.document_designs.create!(doc_type: "chapter")
    ov = ch.paragraph_styles.find_by!(name: "title")
    ov.update!(font_size: 99); ov.mark_overridden(:font_size)
    Design::DefaultGenerator.call(ps)
    assert_equal 99.0, ov.reload.font_size.to_f
  end

  test "regenerate keeps a chapter row's other user fields and rescales an unmarked font_size" do
    base!("title", 24)
    ps = size!
    ch = ps.document_designs.create!(doc_type: "chapter")
    row = ch.paragraph_styles.find_by!(name: "title")
    row.update_columns(font_size: 50, text_color: "red")
    Design::DefaultGenerator.call(ps)
    row.reload
    assert_equal 18.0, row.font_size.to_f
    assert_equal "red", row.text_color
  end
end
