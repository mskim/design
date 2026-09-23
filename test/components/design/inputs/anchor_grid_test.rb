require "test_helper"

class Design::AnchorGridTest < ActiveSupport::TestCase
  Grid = Design::Views::Inputs::AnchorGrid

  def render(**opts)
    Nokogiri::HTML.fragment(Grid.new(name: "object[text_box_anchor_position]", value: 7,
                                     label: "위치", form: "object-section-form", **opts).call)
  end

  def cells(doc) = doc.css("button[data-anchor]")

  test "nine buttons in reading order, the stored one pressed, with locale labels" do
    doc = render
    assert_equal (1..9).map(&:to_s), cells(doc).map { |b| b["data-anchor"] }
    assert_equal "1", cells(doc).first.text.strip
    pressed = cells(doc).select { |b| b["aria-pressed"] == "true" }
    assert_equal [ "7" ], pressed.map { |b| b["data-anchor"] }
    assert_equal I18n.t("design.object_section.anchors.a7"), pressed.first["aria-label"]
    assert_equal I18n.t("design.object_section.anchors.a7"), pressed.first["title"]
    assert_equal "click->design--anchor-grid#pick", cells(doc).first["data-action"]
    assert_equal "cell", cells(doc).first["data-design--anchor-grid-target"]
  end

  test "the hidden input carries the value, the form and the joint fields; the wrapper re-syncs on a morph" do
    doc = render(joint_with: %w[text_box_grid_width text_box_grid_height])
    hidden = doc.at_css("input[type=hidden][name='object[text_box_anchor_position]']")
    assert_equal "7", hidden["value"]
    assert_equal "object-section-form", hidden["form"]
    assert_equal "input", hidden["data-design--anchor-grid-target"]
    assert_equal "text_box_grid_width text_box_grid_height", hidden["data-joint-with"]
    wrapper = doc.at_css("[data-controller='design--anchor-grid']")
    assert_equal "turbo:morph-element->design--anchor-grid#resync", wrapper["data-action"]
    assert_nil render.at_css("input[type=hidden]")["data-joint-with"], "no joint fields, no attribute"
  end

  test "crop mode names the group as a crop point, not a position" do
    group = render.at_css("[role=group]")
    assert_equal I18n.t("design.object_section.position"), group["aria-label"]
    doc = render(crop: true)
    assert_equal I18n.t("design.object_section.crop"), doc.at_css("[role=group]")["aria-label"]
    assert_equal "true", doc.at_css("[data-controller='design--anchor-grid']")["data-crop"]
    assert_nil render.at_css("[data-controller='design--anchor-grid']")["data-crop"]
  end

  test "disabled: every button and the hidden input" do
    doc = render(disabled: true)
    assert cells(doc).all? { |b| b.key?("disabled") }
    assert doc.at_css("input[type=hidden]").key?("disabled")
  end

  test "a nil value presses nothing (a doc type with no effective default)" do
    doc = Nokogiri::HTML.fragment(Grid.new(name: "object[photo_anchor]", value: nil, label: "x").call)
    assert_empty doc.css("button[aria-pressed='true']")
    assert_nil doc.at_css("input[type=hidden]")["value"]
  end
end
