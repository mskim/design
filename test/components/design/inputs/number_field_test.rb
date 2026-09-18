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

  test "min and max attributes are absent when nil" do
    root = render_field(name: "x").at_css("[data-controller='design--scrub-input']")
    refute root.key?("data-design--scrub-input-min-value")
    refute root.key?("data-design--scrub-input-max-value")
  end

  test "an input_data action is appended to the scrub actions, not replacing them" do
    input = render_field(name: nil, input_data: { action: "input->other#go", channel: "c" }).at_css("input")
    actions = input["data-action"].split
    %w[focus->design--scrub-input#remember keydown->design--scrub-input#keydown
       blur->design--scrub-input#commit input->other#go].each { |a| assert_includes actions, a }
    assert_equal "input", input["data-design--scrub-input-target"]
    assert_equal "c", input["data-channel"]
  end

  test "label handles drag end, lost capture and the post-drag click" do
    actions = render_field(name: "x").at_css("label")["data-action"].split
    %w[pointerdown->design--scrub-input#scrubStart pointerup->design--scrub-input#scrubEnd
       lostpointercapture->design--scrub-input#scrubEnd click->design--scrub-input#handleClick].each { |a| assert_includes actions, a }
  end

  test "invalid layout or step raises" do
    assert_raises(ArgumentError) { render_field(name: "x", layout: :wide) }
    assert_raises(ArgumentError) { render_field(name: "x", step: 0) }
    assert_raises(ArgumentError) { render_field(name: "x", step: "0.1") }
  end

  test "invalid outline uses a named group so an enclosing group can't trigger it" do
    doc = render_field(name: "x")
    assert_includes doc.at_css("[data-controller='design--scrub-input']")["class"].split, "group/nf"
    assert_includes doc.at_css("input")["class"], "group-data-[invalid]/nf:border-red-500"
    refute_match(/(^|\s)group-data-\[invalid\]:/, doc.at_css("input")["class"])
  end

  test "the suffix describes the input" do
    doc = render_field(name: "x", unit: :mm)
    suffix = doc.at_css("[data-unit-suffix]")
    assert suffix["id"].present?
    assert_equal suffix["id"], doc.at_css("input")["aria-describedby"]
    refute render_field(name: "x", unit: :none).at_css("input").key?("aria-describedby")
  end

  test "a named field gets a stable id from its name; nameless fields stay random" do
    a = render_field(name: "paragraph_style[font_size]").at_css("input")["id"]
    assert_equal "nf-paragraph_style-font_size", a
    assert_equal a, render_field(name: "paragraph_style[font_size]").at_css("input")["id"], "same name, same id (a morph matches it)"
    refute_equal render_field(name: nil).at_css("input")["id"], render_field(name: nil).at_css("input")["id"]
    assert_equal "given", render_field(name: "x", id: "given").at_css("input")["id"]
  end

  test "dom_key: plain bracket names map directly; anything else gets a hash suffix so distinct names stay distinct" do
    nf = Design::Views::Inputs::NumberField
    assert_equal "paragraph_style-font_size", nf.dom_key("paragraph_style[font_size]")
    assert_equal "a-b-c", nf.dom_key("a[b][c]")
    assert_equal "plain", nf.dom_key("plain")
    hash = ->(name) { Digest::MD5.hexdigest(name)[0, 6] }
    assert_equal "a-b-#{hash.("a.b")}", nf.dom_key("a.b")
    refute_equal nf.dom_key("a.b"), nf.dom_key("a-b"), "a.b and a-b no longer collide"
    refute_equal nf.dom_key("x[a b]"), nf.dom_key("x[a-b]")
    assert_equal "-#{hash.("본문")}", nf.dom_key("본문"), "an empty key gets the hash"
    refute_equal nf.dom_key("본문"), nf.dom_key("제목")
  end

  test "an empty name counts as unnamed: a random id" do
    refute_equal render_field(name: "").at_css("input")["id"], render_field(name: "").at_css("input")["id"]
  end

  test "the placeholder (an inherited value) is grey italic, and the field re-syncs after a morph" do
    doc = render_field(name: "x", placeholder: "10.0")
    classes = doc.at_css("input")["class"].split
    assert_includes classes, "placeholder:italic"
    assert_includes classes, "placeholder:text-slate-400"
    assert_includes doc.at_css("[data-controller='design--scrub-input']")["data-action"],
                    "turbo:morph-element->design--scrub-input#resync"
  end

  test "form: associates the input with another form (the Page section's)" do
    assert_equal "page-section-form", render_field(name: "page[top_margin_mm]", form: "page-section-form").at_css("input")["form"]
    refute render_field(name: "x").at_css("input").key?("form")
  end
end
