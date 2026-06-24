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
    assert_includes html, %(data-controller="design--color-mode-field")
    assert_includes html, %(data-controller="design--border-side-editor")
    assert_includes html, %(data-controller="design--corner-editor")
    assert_includes html, %(name="paragraph_style[border_side]")
    assert_includes html, %(name="paragraph_style[corner_radius]")
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

  # ── Interactive border/corner widgets (KEEP — not plain text inputs) ──

  test "border section renders interactive border-side-editor (not plain text input)" do
    html = Design::Views::ParagraphStyles::Fields.new(paragraph_style: @style).call
    assert_includes html, %(data-controller="design--border-side-editor")
    # The toggle buttons must be present
    assert_includes html, %(click->design--border-side-editor#toggle)
    # The hidden accumulator input must be present
    assert_includes html, %(name="paragraph_style[border_side]")
  end

  test "border section renders interactive corner-editor (not plain text input)" do
    html = Design::Views::ParagraphStyles::Fields.new(paragraph_style: @style).call
    assert_includes html, %(data-controller="design--corner-editor")
    assert_includes html, %(click->design--corner-editor#toggle)
    assert_includes html, %(name="paragraph_style[rounded_corners]")
    assert_includes html, %(name="paragraph_style[corner_radius]")
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

  test "editable: false — color mode field inputs carry disabled" do
    html = Design::Views::ParagraphStyles::Fields.new(paragraph_style: @style, editable: false).call
    # The color text input (e.g. text_color) must be present and disabled must appear in the html
    assert_includes html, %(name="paragraph_style[text_color]")
    # disabled appears on the color picker and mode select inside the color-mode-field controller
    assert_match(/data-controller="design--color-mode-field".*?disabled/m, html)
  end

  test "editable: false — border-side-editor buttons carry disabled" do
    html = Design::Views::ParagraphStyles::Fields.new(paragraph_style: @style, editable: false).call
    # There should be disabled on the buttons inside the border-side-editor
    assert_includes html, %(data-controller="design--border-side-editor")
    assert_match(/click->design--border-side-editor#toggle[^>]*disabled|disabled[^>]*click->design--border-side-editor#toggle/, html)
  end

  test "editable: false — corner-editor buttons carry disabled" do
    html = Design::Views::ParagraphStyles::Fields.new(paragraph_style: @style, editable: false).call
    assert_includes html, %(data-controller="design--corner-editor")
    assert_match(/click->design--corner-editor#toggle[^>]*disabled|disabled[^>]*click->design--corner-editor#toggle/, html)
  end

  test "editable: false — corner_radius select carries disabled" do
    html = Design::Views::ParagraphStyles::Fields.new(paragraph_style: @style, editable: false).call
    assert_match(/name="paragraph_style\[corner_radius\]"[^>]*disabled|disabled[^>]*name="paragraph_style\[corner_radius\]"/, html)
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

  test "editable: true — border-side-editor buttons are NOT disabled" do
    html = Design::Views::ParagraphStyles::Fields.new(paragraph_style: @style, editable: true).call
    refute_match(/click->design--border-side-editor#toggle[^>]*disabled/, html)
  end

  test "editable: true — corner-editor buttons are NOT disabled" do
    html = Design::Views::ParagraphStyles::Fields.new(paragraph_style: @style, editable: true).call
    refute_match(/click->design--corner-editor#toggle[^>]*disabled/, html)
  end
end
