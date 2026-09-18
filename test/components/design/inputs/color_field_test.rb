require "test_helper"

class Design::ColorFieldTest < ActiveSupport::TestCase
  def render_field(value:, **opts)
    Nokogiri::HTML.fragment(Design::Views::Inputs::ColorField.new(name: "paragraph_style[text_color]", value: value, label: "색", **opts).call)
  end

  test "hidden input carries the stored text unchanged" do
    doc = render_field(value: "CMYK=0,0,0,100")
    hidden = doc.at_css("input[type=hidden][name='paragraph_style[text_color]']")
    assert_equal "CMYK=0,0,0,100", hidden["value"]
    assert_equal "C0 M0 Y0 K100", doc.at_css("[data-design--color-row-target='summary']").text.strip
    assert_equal "design--color-row", doc.at_css("[data-controller]")["data-controller"]
  end

  test "summary for hex, legacy name and empty" do
    assert_equal "#3b82f6", render_field(value: "#3b82f6").at_css("[data-design--color-row-target='summary']").text.strip
    assert_equal "white", render_field(value: "white").at_css("[data-design--color-row-target='summary']").text.strip
    assert_equal I18n.t("design.inputs.inherit"), render_field(value: "").at_css("[data-design--color-row-target='summary']").text.strip
  end

  test "popover sub-fields submit nothing" do
    doc = render_field(value: "CMYK=0,0,0,100")
    popover = doc.at_css("[data-design--color-row-target='popover']")
    assert popover.key?("hidden")
    assert_equal 4, popover.css("input[data-channel]").size
    assert_empty popover.css("input[name]"), "popover inputs must not have names"
  end

  test "mode switch only with two formats; hex-only renders no CMYK panel" do
    assert_equal 2, render_field(value: "").css("[data-mode]").size
    hex_only = render_field(value: "#ffffff", formats: [ :hex ])
    assert_empty hex_only.css("[data-mode]")
    assert_nil hex_only.at_css("[data-design--color-row-target='cmykPanel']")
    assert hex_only.at_css("[data-design--color-row-target='hexInput']")
    assert_equal "hex", hex_only.at_css("[data-controller]")["data-design--color-row-formats-value"]
  end

  test "disabled disables the trigger and the hidden input" do
    doc = render_field(value: "#000000", disabled: true)
    assert doc.at_css("button[data-design--color-row-target='trigger']").key?("disabled")
    assert doc.at_css("input[type=hidden]").key?("disabled")
  end
end
