require "test_helper"

class Design::BorderEditorsTest < ActiveSupport::TestCase
  def html(klass, **opts) = Nokogiri::HTML.fragment(klass.new(**opts).call)

  test "border sides: the hidden input keeps the name; an inherited value leaves it empty and rides the parent's sides" do
    doc = html(Design::Views::Inputs::BorderSides, name: "paragraph_style[border_side]", value: nil, inherited_value: "1,0,1,0")
    root = doc.at_css("[data-controller='design--border-side-editor']")
    assert_equal "1,0,1,0", root["data-design--border-side-editor-parent-value"]
    assert_includes root["data-action"], "turbo:morph-element->design--border-side-editor#updateVisual"
    input = doc.at_css("input[type=hidden][name='paragraph_style[border_side]']")
    assert_nil input["value"]
    assert_equal %w[top left right bottom], doc.css("button[data-side]").map { |b| b["data-side"] }
  end

  test "border sides: an own value, and no parent attribute without a parent" do
    doc = html(Design::Views::Inputs::BorderSides, name: "paragraph_style[border_side]", value: "1,1,1,1")
    assert_equal "1,1,1,1", doc.at_css("input[type=hidden]")["value"]
    refute doc.at_css("[data-controller]").key?("data-design--border-side-editor-parent-value")
  end

  test "corners: same contract" do
    doc = html(Design::Views::Inputs::Corners, name: "paragraph_style[rounded_corners]", value: nil, inherited_value: "1,0,0,1")
    root = doc.at_css("[data-controller='design--corner-editor']")
    assert_equal "1,0,0,1", root["data-design--corner-editor-parent-value"]
    assert_includes root["data-action"], "turbo:morph-element->design--corner-editor#updateVisual"
    assert doc.at_css("input[type=hidden][name='paragraph_style[rounded_corners]']")
    assert_equal %w[tl tr bl br], doc.css("button[data-corner]").map { |b| b["data-corner"] }
  end

  test "disabled editors disable the input and every button" do
    [ Design::Views::Inputs::BorderSides, Design::Views::Inputs::Corners ].each do |klass|
      doc = html(klass, name: "x", value: nil, disabled: true)
      assert doc.at_css("input[type=hidden][disabled]"), klass.name
      assert doc.css("button").all? { |b| b.key?("disabled") }, klass.name
    end
  end
end
