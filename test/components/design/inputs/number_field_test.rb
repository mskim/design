require "test_helper"

class Design::NumberFieldTest < ActiveSupport::TestCase
  def render_field(**opts)
    Nokogiri::HTML.fragment(Design::Views::Inputs::NumberField.new(value: "12", label: "크기", **opts).call)
  end

  test "renders a named text input with the original value, a label handle and the controller" do
    doc = render_field(name: "paragraph_style[font_size]", unit: :pt, step: 0.1)
    input = doc.at_css("input[name='paragraph_style[font_size]']")
    assert input, "named input missing"
    assert_equal "text", input["type"]
    assert_equal "decimal", input["inputmode"]
    assert_equal "12", input["value"]
    root = doc.at_css("[data-controller='design--scrub-input']")
    assert_equal "pt", root["data-design--scrub-input-unit-value"]
    assert_equal "0.1", root["data-design--scrub-input-step-value"]
    handle = doc.at_css("label[data-design--scrub-input-target='handle']")
    assert_equal "크기", handle.text.strip
    assert_equal input["id"], handle["for"]
  end

  test "unit suffixes" do
    { pt: "pt", mm: "mm", percent: "%" }.each do |unit, text|
      assert_equal text, render_field(name: "x", unit: unit).at_css("[data-unit-suffix]").text.strip, unit.to_s
    end
    assert_equal I18n.t("design.inputs.lines"), render_field(name: "x", unit: :lines).at_css("[data-unit-suffix]").text.strip
    assert_nil render_field(name: "x", unit: :none).at_css("[data-unit-suffix]")
  end

  test "no name attribute when name is nil" do
    refute render_field(name: nil).at_css("input[name]")
  end

  test "min, max, placeholder, disabled and span" do
    doc = render_field(name: "x", min: 1, max: 12, placeholder: "4", disabled: true, span: true)
    root = doc.at_css("[data-controller='design--scrub-input']")
    assert_equal "1", root["data-design--scrub-input-min-value"]
    assert_equal "12", root["data-design--scrub-input-max-value"]
    assert_includes root["class"], "col-span-2"
    input = doc.at_css("input")
    assert_equal "4", input["placeholder"]
    assert input.key?("disabled")
  end

  test "layouts render" do
    %i[inline stacked compact].each do |layout|
      assert render_field(name: "x", layout: layout).at_css("input[name='x']"), layout.to_s
    end
  end

  test "input_data is merged onto the input" do
    input = render_field(name: nil, input_data: { channel: "c" }).at_css("input")
    assert_equal "c", input["data-channel"]
  end
end
