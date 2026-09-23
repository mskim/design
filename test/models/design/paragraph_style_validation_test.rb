require "test_helper"

class Design::ParagraphStyleValidationTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "V #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.find_by(doc_type: "chapter") || @ps.document_designs.create!(doc_type: "chapter")
  end

  def row(**attrs) = @dd.paragraph_styles.new(name: "zz_v", **attrs)
  def panel_valid?(record) = record.valid?(:style_panel)

  test "a numeric style field must be a plain decimal (decimal columns would cast 'abc' to 0)" do
    r = row(font_size: "abc")
    refute panel_valid?(r)
    assert_includes r.errors[:font_size], I18n.t("design.style_panel.errors.not_a_number")
    %w[12pt 0x1A 1_0 1,5].each { |v| refute panel_valid?(row(space_before: v)), v }
  end

  test "sizes and spacing can't be negative; indents and tracking can" do
    r = row(space_after: "-1")
    refute panel_valid?(r)
    assert_includes r.errors[:space_after], I18n.t("design.style_panel.errors.negative")
    assert panel_valid?(row(first_line_indent: "-10", left_indent: "-2", tracking: "-0.5"))
  end

  test "blank, padded, signed and fractional numbers are fine" do
    [ "", " 10.5 ", "+3.5", ".5", "1." ].each { |v| assert panel_valid?(row(font_size: v)), v.inspect }
    [ "-0.5", "+2" ].each { |v| assert panel_valid?(row(tracking: v)), v.inspect }
  end

  test "exponent notation is not a plain decimal (1e999 would be Infinity)" do
    %w[1e1 +3.5E-2 1e999].each do |v|
      r = row(font_size: v)
      refute panel_valid?(r), v
      assert_includes r.errors[:font_size], I18n.t("design.style_panel.errors.not_a_number"), v
    end
  end

  test "numbers are bounded to ±10000" do
    r = row(font_size: "99999")
    refute panel_valid?(r)
    assert_includes r.errors[:font_size], I18n.t("design.style_panel.errors.too_large", max: 10_000)
    refute panel_valid?(row(first_line_indent: "-10000.5"))
    assert panel_valid?(row(first_line_indent: "-10000", space_before: "10000"))
  end

  test "space_width can't be negative; font_size and scale must be positive" do
    r = row(space_width: "-1")
    refute panel_valid?(r)
    assert_includes r.errors[:space_width], I18n.t("design.style_panel.errors.negative")
    %w[font_size scale].each do |f|
      r = row(f => "0")
      refute panel_valid?(r), f
      assert_includes r.errors[f], I18n.t("design.style_panel.errors.positive"), f
    end
    assert panel_valid?(row(space_width: "0", space_before: "0", font_size: "0.1", scale: "1"))
  end

  test "select fields take only the options the panel offers" do
    { text_align: Design::ParagraphStyle::TEXT_ALIGNS, fill_type: Design::ParagraphStyle::FILL_TYPES,
      fill_gradient_direction: Design::ParagraphStyle::GRADIENT_DIRECTIONS,
      corner_top_left: Design::ParagraphStyle::CORNER_SIZES }.each do |f, options|
      options.each { |v| assert panel_valid?(row(f => v)), "#{f}=#{v}" }
      r = row(f => "banana")
      refute panel_valid?(r), f
      assert_includes r.errors[f], I18n.t("design.style_panel.errors.invalid_option"), f
    end
  end

  test "fonts: an available font, or the value already stored on this row or its parent (legacy fonts round-trip)" do
    assert panel_valid?(row(font: Design::Theme::AVAILABLE_FONTS.first, bold_font: Design::Theme::AVAILABLE_FONTS.last))
    r = row(emphasis_font: "Comic Sans")
    refute panel_valid?(r)
    assert_includes r.errors[:emphasis_font], I18n.t("design.style_panel.errors.invalid_option")

    legacy = @dd.paragraph_styles.create!(name: "zz_legacy_font", font: "OldFont")
    legacy.reload.font = "OldFont"
    assert panel_valid?(legacy), "this row's stored value"
    legacy.font = "OtherOldFont"
    refute panel_valid?(legacy)

    @theme.base_paragraph_styles.create!(name: "zz_v", bold_font: "ParentFont")
    assert panel_valid?(row(bold_font: "ParentFont")), "the parent's value"
    refute panel_valid?(row(font: "ParentFont")), "per field: the parent's font is not the parent's bold_font"
  end

  test "colours: CMYK=c,m,y,k, #rrggbb or a legacy name (what ColorValue reads)" do
    Design::ParagraphStyle::COLOR_FIELDS.each do |f|
      [ "CMYK=0,0,0,100", "CMYK=10.5,0,.5,100", "CMYK= 1 , 2 ,3,4", "#1a2B3c", "black", "Gray" ].each do |v|
        assert panel_valid?(row(f => v)), "#{f}=#{v}"
        assert Design::Views::Inputs::ColorValue.format(v), "ColorValue reads #{v}"
      end
      [ "CMYK=0,0,0", "CMYK=a,0,0,0", "cmyk=0,0,0,0", "#12345", "#1234567", "purple", "CMYK=" ].each do |v|
        r = row(f => v)
        refute panel_valid?(r), "#{f}=#{v}"
        assert_includes r.errors[f], I18n.t("design.style_panel.errors.invalid_color"), f
      end
    end
  end

  test "only assigned fields are checked: a legacy value never blocks another edit" do
    r = @dd.paragraph_styles.create!(name: "zz_legacy", font_size: 10)
    r.update_columns(space_before: -3)
    r.reload.font_size = 11
    assert panel_valid?(r)
  end

  test "outside the :style_panel context nothing is checked (importers, generator, set_style_field!)" do
    assert row(font_size: "abc").valid?
  end

  test "theme base rows are never checked (their forms are unchanged)" do
    assert panel_valid?(@theme.base_paragraph_styles.new(name: "zz_t", font_size: "abc"))
  end
end
