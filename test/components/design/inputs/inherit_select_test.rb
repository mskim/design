require "test_helper"

class Design::InheritSelectTest < ActiveSupport::TestCase
  def render_select(**opts)
    Nokogiri::HTML.fragment(Design::Views::Inputs::InheritSelect.new(
      name: "paragraph_style[text_align]", options: %w[left center right justify], i18n_scope: "text_align", **opts).call)
  end

  test "inherited: the blank first option names the parent value and is selected" do
    doc = render_select(value: nil, inherited_value: "center")
    first = doc.css("option").first
    assert_equal "", first["value"]
    assert first.key?("selected")
    assert_equal I18n.t("design.inputs.inherit_with_value", value: I18n.t("design.options.text_align.center")), first.text
    assert doc.at_css("select").key?("data-inherited")
    assert_equal "paragraph_style[text_align]", doc.at_css("select")["name"]
  end

  test "no parent value: the first option is just the inherit label" do
    assert_equal I18n.t("design.inputs.inherit"), render_select(value: nil).css("option").first.text
  end

  test "an own value is selected and the select isn't marked inherited" do
    doc = render_select(value: "right", inherited_value: "center")
    assert doc.at_css("option[value=right]").key?("selected")
    refute doc.css("option").first.key?("selected")
    refute doc.at_css("select").key?("data-inherited")
  end

  test "a current value missing from the options is kept so it round-trips" do
    doc = render_select(value: "distributed")
    assert doc.at_css("option[value=distributed][selected]")
  end

  test "disabled" do
    assert render_select(value: nil, disabled: true).at_css("select[disabled]")
  end
end
