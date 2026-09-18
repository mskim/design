require "test_helper"

class Design::SizeGenerationServiceTest < ActiveSupport::TestCase
  FIELDS = Design::ParagraphStyle::STYLE_FIELDS

  setup do
    @theme = Design::Theme.create!(name: "SG #{SecureRandom.hex(3)}", locale: "ko")
    base!("body", font: "BaseFont", font_size: 10, text_color: "black", space_before: 0, space_after: 0)
    base!("title", font_size: 24)
    # Default size = first by id.
    @default = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @target  = @theme.paper_sizes.create!(size_name: "A4", width_mm: 210, height_mm: 297)
    @default_ch = @default.document_designs.create!(doc_type: "chapter")
    @target_ch  = @target.document_designs.create!(doc_type: "chapter")
    @ratio_h = 297.0 / 225.0
  end

  def base!(name, **attrs) = @theme.base_paragraph_styles.create!(name: name, **attrs)
  def generate! = Design::SizeGenerationService.new(@theme).generate!
  def set_fields(row) = FIELDS.select { |f| !row[f].nil? }.sort

  test "default size is the theme's first paper size" do
    assert_equal @default, @theme.default_paper_size
  end

  test "a sparse default chapter body (font_size from theme) still recomputes body_line_count" do
    assert_nil @default_ch.paragraph_styles.find_by(name: "body")
    @target.update_columns(body_line_count: 5)

    generate!
    @target.reload; @default.reload

    line_height = @default.content_height_pt / @default.body_line_count
    expected = [ (@target.content_height_pt / line_height).floor, 10 ].max
    assert_equal expected, @target.body_line_count
    refute_equal 5, expected
  end

  test "target chapter rows hold only fields that differ from the theme base after scaling" do
    row = @default_ch.paragraph_styles.create!(name: "body", text_color: "red", space_after: 10)
    row.update_columns(font: "BaseFont") # equal to the theme base (legacy snapshot value)
    stale = @target_ch.paragraph_styles.create!(name: "body", font: "Stale", tracking: 3)

    generate!
    body = @target_ch.paragraph_styles.find_by!(name: "body")

    assert_equal stale.id, body.id
    assert_equal "red", body.text_color
    assert_in_delta 10 * @ratio_h, body.space_after.to_f, 0.01
    assert_nil body.font, "equal to the theme base → inherit"
    assert_nil body.font_size, "body size stays the same as the base → inherit"
    assert_nil body.tracking, "stale field not in the resolved default is cleared"
    assert_equal %w[space_after text_color], set_fields(body)
  end

  test "a heading scaled differently per size is stored on the target chapter" do
    default_title = @default_ch.paragraph_styles.find_by!(name: "title").font_size.to_f   # generator: 24 × 0.75
    assert_equal 18.0, default_title

    generate!
    title = @target_ch.paragraph_styles.find_by!(name: "title")
    assert_in_delta (default_title * @ratio_h).round(2), title.font_size.to_f, 0.001
    assert_equal %w[font_size], set_fields(title)
  end

  test "a chapter style that ends up equal to the theme base has no target row" do
    base!("caption", font: "CapFont")   # nothing to scale, nothing overridden
    @target_ch.paragraph_styles.create!(name: "caption", font: "CapFont")

    generate!
    assert_nil @target_ch.paragraph_styles.find_by(name: "caption")
  end

  test "target non-chapter rows hold only the default size's own non-nil fields; nothing inherited is copied" do
    @default_ch.paragraph_styles.create!(name: "body", text_color: "red")
    fw = @default.document_designs.create!(doc_type: "foreword")
    fw.paragraph_styles.create!(name: "body", text_color: "green", space_before: 6)
    fw.paragraph_styles.create!(name: "title", font_size: 20)

    target_fw = @target.document_designs.create!(doc_type: "foreword")
    target_fw.paragraph_styles.create!(name: "body", font: "Stale", font_size: 99, text_color: "blue")

    generate!
    rows = target_fw.paragraph_styles.reload.index_by(&:name)

    assert_equal %w[body title], rows.keys.sort, "no rows for styles the default only inherits"
    assert_equal "green", rows["body"].text_color
    assert_in_delta 6 * @ratio_h, rows["body"].space_before.to_f, 0.01
    assert_equal %w[space_before text_color], set_fields(rows["body"])
    assert_in_delta (20 * @ratio_h).round(2), rows["title"].font_size.to_f, 0.001
    assert_equal %w[font_size], set_fields(rows["title"])
  end

  test "a non-chapter doc type missing on the target is created sparse" do
    fw = @default.document_designs.create!(doc_type: "foreword")
    fw.paragraph_styles.create!(name: "body", text_color: "green")

    generate!
    target_fw = @target.document_designs.find_by!(doc_type: "foreword")
    assert_equal %w[body], target_fw.paragraph_styles.pluck(:name)
    assert_equal %w[text_color], set_fields(target_fw.paragraph_styles.first)
  end
end
