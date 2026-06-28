require "test_helper"

class Design::FieldsLayoutTest < ActiveSupport::TestCase
  def fragment(name: "title")
    theme = Design::Theme.create!(name: "FX #{SecureRandom.hex(3)}", locale: "ko")
    style = theme.base_paragraph_styles.create!(
      name: name, font_size: 24, text_color: "CMYK=0,0,0,100", border_thickness: 5
    )
    Nokogiri::HTML.fragment(Design::Views::ParagraphStyles::Fields.new(paragraph_style: style).call)
  end

  test "each group renders as a fieldset box with a legend" do
    f = fragment
    groups = f.css("fieldset[data-group]")
    assert_operator groups.size, :>=, 7, "expected the 7 base groups as fieldset boxes"
    groups.each { |g| assert g.at_css("legend"), "box #{g['data-group']} missing legend" }
  end

  test "font and text merge into one type_text box holding both controls" do
    f = fragment
    assert_equal 0, f.css('fieldset[data-group="font"], fieldset[data-group="text"]').size,
      "font/text should no longer be separate boxes"
    box = f.at_css('fieldset[data-group="type_text"]')
    assert box, "merged 글꼴 · 텍스트 box present"
    assert box.at_css('[name="paragraph_style[font]"]'), "font control inside the merged box"
    assert box.at_css('[name="paragraph_style[text_color]"]'), "text color inside the merged box"
  end

  test "fields are inline rows (label + control share a row)" do
    f = fragment
    row = f.at_css(".ps-field")
    assert row, "inline field row present"
    assert row.at_css("label"), "row has a label"
    assert row.at_css("input, select"), "row has a control"
  end

  test "border editors and corner radius stay inside the border box" do
    f = fragment
    box = f.at_css('fieldset[data-group="border"]')
    assert box, "border box present"
    assert box.at_css('[data-controller~="design--border-side-editor"]')
    assert box.at_css('[data-controller~="design--corner-editor"]')
    assert box.at_css('[name="paragraph_style[corner_radius]"]')
  end
end
