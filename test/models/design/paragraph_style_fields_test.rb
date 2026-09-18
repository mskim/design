require "test_helper"

class Design::ParagraphStyleFieldsTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "F #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.find_by(doc_type: "chapter") || @ps.document_designs.create!(doc_type: "chapter")
  end

  test "STYLE_FIELDS excludes name, korean_name and vertical_align" do
    f = Design::ParagraphStyle::STYLE_FIELDS
    refute_includes f, "name"
    refute_includes f, "korean_name"
    refute_includes f, "vertical_align"
    assert_includes f, "font_size"
    assert_includes f, "text_color"
  end

  test "doc-type rows store blank strings as nil" do
    row = @dd.paragraph_styles.create!(name: "zz_blank", font: "", text_align: "  ", text_color: "")
    assert_nil row.reload.font
    assert_nil row.text_align
    assert_nil row.text_color
  end

  test "doc-type rows are created with every STYLE_FIELD nil except those given" do
    row = @dd.paragraph_styles.create!(name: "zz_sparse", font_size: 9)
    assert_equal 9, row.reload.font_size.to_i
    assert_nil row.scale, "DB default scale must not be stored on doc-type rows"
    assert_nil row.text_color, "DB default text_color must not be stored on doc-type rows"
  end

  test "a persisted doc-type row's dup keeps its stored scale and text_color" do
    row = @dd.paragraph_styles.create!(name: "zz_dup", scale: 90, text_color: "CMYK=0,100,0,0")
    copy = Design::ParagraphStyle.find(row.id).dup
    assert_equal 90, copy.scale.to_i
    assert_equal "CMYK=0,100,0,0", copy.text_color
  end

  test "SCALED_FIELDS are pt-valued style fields only" do
    f = Design::ParagraphStyle::SCALED_FIELDS
    assert (f - Design::ParagraphStyle::STYLE_FIELDS).empty?
    assert_includes f, "font_size"
    %w[tracking scale space_before_in_lines border_thickness corner_radius].each { |x| refute_includes f, x }
  end

  test "theme base rows keep their defaults and blanks untouched" do
    base = @theme.base_paragraph_styles.create!(name: "zz_base")
    assert_equal 100, base.reload.scale.to_i
    assert_equal "CMYK=0,0,0,100", base.text_color
  end

  test "same_value? compares typed values" do
    sv = Design::ParagraphStyle.method(:same_value?)
    assert sv.call("font_size", BigDecimal("10.0"), "10")
    assert sv.call("font", " Shinmoon ", "Shinmoon")
    refute sv.call("font_size", 10, 10.5)
    assert sv.call("text_color", "CMYK=0,0,0,100", "CMYK=0,0,0,100")
    refute sv.call("text_color", "CMYK=0,0,0,100", "#000000")
    assert sv.call("font", nil, "")
  end
end
