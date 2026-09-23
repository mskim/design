require "test_helper"

class Design::ParagraphFieldsTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "F #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @style = @ps.paragraph_styles.create!(name: "body", font_size: 10)
  end

  test "Fields renders all groups with paragraph_style names + host controllers" do
    html = Design::Views::ParagraphStyles::Fields.new(paragraph_style: @style).call
    assert_includes html, %(name="paragraph_style[name]")
    assert_includes html, %(name="paragraph_style[font_size]")
    assert_includes html, %(name="paragraph_style[text_color]")
    assert_includes html, %(data-controller="design--color-row")
    assert_includes html, %(data-controller="design--scrub-input")
  end

  test "non-negative number fields get min 0; indents and tracking stay unbounded" do
    doc = Nokogiri::HTML.fragment(Design::Views::ParagraphStyles::Fields.new(paragraph_style: @style).call)
    min_of = ->(attr) { doc.at_css("input[name='paragraph_style[#{attr}]']").ancestors("[data-controller='design--scrub-input']").first["data-design--scrub-input-min-value"] }
    %w[font_size scale text_line_spacing space_before space_after space_before_in_lines space_after_in_lines
       border_top_thickness padding_top padding_bottom].each { |attr| assert_equal "0", min_of.(attr), attr }
    %w[first_line_indent left_indent right_indent tracking space_width].each { |attr| assert_nil min_of.(attr), attr }
  end

  # ── vertical_align (table cells only) ──

  test "vertical_align select renders for a table_body_cell style" do
    style = @ps.paragraph_styles.create!(name: "table_body_cell", font_size: 9)
    html = Design::Views::ParagraphStyles::Fields.new(paragraph_style: style).call
    assert_includes html, %(name="paragraph_style[vertical_align]")
  end

  test "vertical_align select is absent for a body style" do
    html = Design::Views::ParagraphStyles::Fields.new(paragraph_style: @style).call
    refute_includes html, %(name="paragraph_style[vertical_align]")
  end

  # ── fill gradient direction: renderer vocabulary (merged with book_design) ──

  test "gradient direction uses the renderer vocabulary + angle (not horizontal/vertical/diagonal)" do
    html = Design::Views::ParagraphStyles::Fields.new(paragraph_style: @style).call
    %w[top_to_bottom bottom_to_top left_to_right right_to_left angle].each do |opt|
      assert_includes html, %(value="#{opt}"), "expected merged gradient option #{opt}"
    end
    refute_includes html, %(value="diagonal")
    refute_includes html, %(value="horizontal")
  end

  test "border section: a thickness and a colour per side, a preset select per corner" do
    html = Design::Views::ParagraphStyles::Fields.new(paragraph_style: @style).call
    Design::ParagraphStyle::SIDES.each do |s|
      assert_includes html, %(name="paragraph_style[border_#{s}_thickness]")
      assert_includes html, %(name="paragraph_style[border_#{s}_color]")
    end
    Design::ParagraphStyle::CORNERS.each { |c| assert_includes html, %(name="paragraph_style[corner_#{c}]") }
  end

  test "padding section renders" do
    html = Design::Views::ParagraphStyles::Fields.new(paragraph_style: @style).call
    assert_includes html, %(name="paragraph_style[padding_top]")
    assert_includes html, %(name="paragraph_style[padding_bottom]")
  end

  # ── Read-only threading (editable: false) ──

  test "editable: false — text inputs carry disabled" do
    html = Design::Views::ParagraphStyles::Fields.new(paragraph_style: @style, editable: false).call
    assert_match(/name="paragraph_style\[name\]"[^>]*disabled|disabled[^>]*name="paragraph_style\[name\]"/, html)
    assert_match(/name="paragraph_style\[font_size\]"[^>]*disabled|disabled[^>]*name="paragraph_style\[font_size\]"/, html)
  end

  test "editable: false — select fields carry disabled" do
    html = Design::Views::ParagraphStyles::Fields.new(paragraph_style: @style, editable: false).call
    assert_match(/name="paragraph_style\[text_align\]"[^>]*disabled|disabled[^>]*name="paragraph_style\[text_align\]"/, html)
  end

  test "editable: false — color row controls carry disabled" do
    html = Design::Views::ParagraphStyles::Fields.new(paragraph_style: @style, editable: false).call
    # The colour row is present, its hidden value input (e.g. text_color) is disabled
    assert_includes html, %(data-controller="design--color-row")
    assert_match(/name="paragraph_style\[text_color\]"[^>]*disabled|disabled[^>]*name="paragraph_style\[text_color\]"/, html)
    # and the popover trigger button is disabled
    assert_match(/data-design--color-row-target="trigger"[^>]*disabled|disabled[^>]*data-design--color-row-target="trigger"/, html)
  end

  test "editable: false — corner_top_left select carries disabled" do
    html = Design::Views::ParagraphStyles::Fields.new(paragraph_style: @style, editable: false).call
    assert_match(/name="paragraph_style\[corner_top_left\]"[^>]*disabled|disabled[^>]*name="paragraph_style\[corner_top_left\]"/, html)
  end

  test "editable: false — padding inputs carry disabled" do
    html = Design::Views::ParagraphStyles::Fields.new(paragraph_style: @style, editable: false).call
    assert_match(/name="paragraph_style\[padding_top\]"[^>]*disabled|disabled[^>]*name="paragraph_style\[padding_top\]"/, html)
    assert_match(/name="paragraph_style\[padding_bottom\]"[^>]*disabled|disabled[^>]*name="paragraph_style\[padding_bottom\]"/, html)
  end

  # ── Editable: true — no disabled ──

  test "editable: true (default) — font_size input is NOT disabled" do
    html = Design::Views::ParagraphStyles::Fields.new(paragraph_style: @style).call
    refute_match(/name="paragraph_style\[font_size\]"[^>]*disabled/, html)
  end
end
