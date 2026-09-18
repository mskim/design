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

  test "blank, padded, signed, fractional and exponent numbers are fine" do
    [ "", " 10.5 ", "1e1", "+3.5E-2", ".5", "1." ].each { |v| assert panel_valid?(row(font_size: v)), v.inspect }
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
