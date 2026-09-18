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

  test "trigger is labelled by the label and summary and controls the dialog popover" do
    doc = render_field(value: "#3b82f6")
    trigger = doc.at_css("[data-design--color-row-target='trigger']")
    label_id, summary_id = trigger["aria-labelledby"].split
    assert_equal "색", doc.at_css("##{label_id}").text.strip
    assert_equal doc.at_css("[data-design--color-row-target='summary']"), doc.at_css("##{summary_id}")
    assert_equal "dialog", trigger["aria-haspopup"]
    assert_equal "false", trigger["aria-expanded"]
    popover = doc.at_css("##{trigger['aria-controls']}")
    assert_equal popover, doc.at_css("[data-design--color-row-target='popover']")
    assert_equal "dialog", popover["role"]
    assert_equal "색", popover["aria-label"]
    assert_equal "true", doc.at_css("[data-design--color-row-target='swatch']")["aria-hidden"]
    assert_equal "K", doc.at_css("[data-design--color-row-target='kSlider']")["aria-label"]
    assert_equal "Hex", doc.at_css("[data-design--color-row-target='hexInput']")["aria-label"]
    assert(doc.css("[data-mode]").all? { |b| b["aria-pressed"] == "false" })
  end

  test "nameless rows get distinct ids" do
    [ nil, "" ].each do |name|
      ids = 2.times.map do
        Nokogiri::HTML.fragment(Design::Views::Inputs::ColorField.new(name: name, value: "", label: "색").call)
                  .at_css("[data-design--color-row-target='popover']")["id"]
      end
      refute_equal ids.first, ids.last, name.inspect
    end
  end

  test "cmyk panel remembers the stored value on focus and reverts it on a channel revert" do
    actions = render_field(value: "").at_css("[data-design--color-row-target='cmykPanel']")["data-action"].split
    assert_includes actions, "focusin->design--color-row#rememberField"
    assert_includes actions, "design--scrub-input:revert->design--color-row#revertField"
    assert_includes actions, "change->design--color-row#commitChannels"
  end

  test "picker commits on input and change; Escape is handled at document level, not the root" do
    doc = render_field(value: "")
    assert_equal "input->design--color-row#fromPicker change->design--color-row#fromPicker",
                 doc.at_css("[data-design--color-row-target='picker']")["data-action"]
    assert_nil doc.at_css("[data-controller]")["data-action"]
  end

  test "disabled disables the trigger and the hidden input" do
    doc = render_field(value: "#000000", disabled: true)
    assert doc.at_css("button[data-design--color-row-target='trigger']").key?("disabled")
    assert doc.at_css("input[type=hidden]").key?("disabled")
  end

  test "an inherited colour shows the parent's swatch and summary, marked inherited" do
    doc = render_field(value: "", inherited_value: "CMYK=0,100,0,0")
    assert_equal "", doc.at_css("input[type=hidden]")["value"].to_s, "no own value is stored"
    summary = doc.at_css("[data-design--color-row-target='summary']")
    assert_equal "C0 M100 Y0 K0", summary.text.strip
    assert summary.key?("data-inherited")
    assert_includes doc.at_css("[data-design--color-row-target='swatch']")["style"],
                    Design::Views::Inputs::ColorValue.swatch_hex("CMYK=0,100,0,0")
    assert_equal "CMYK=0,100,0,0", doc.at_css("[data-controller='design--color-row']")["data-design--color-row-parent-value"]
  end

  test "an own colour is not marked inherited; no parent means the plain inherit label" do
    refute render_field(value: "CMYK=0,0,0,100", inherited_value: "CMYK=0,100,0,0")
             .at_css("[data-design--color-row-target='summary']").key?("data-inherited")
    doc = render_field(value: "")
    assert_equal I18n.t("design.inputs.inherit"), doc.at_css("[data-design--color-row-target='summary']").text.strip
    refute doc.at_css("[data-controller='design--color-row']").key?("data-design--color-row-parent-value")
  end

  test "a named colour row has stable ids, channel sub-fields included" do
    doc = render_field(value: "")
    assert_equal "cf-paragraph_style-text_color-popover", doc.at_css("[data-design--color-row-target='popover']")["id"]
    assert_equal %w[c m y k].map { |ch| "cf-paragraph_style-text_color-#{ch}" },
                 doc.css("input[data-channel]").map { |i| i["id"] }
  end
end
