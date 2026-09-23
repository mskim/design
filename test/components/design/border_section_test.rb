require "test_helper"

# D5: the 테두리 section — two 🔗 boxes (border, corners), linked rows that
# write a whole group, split rows that are ordinary style fields, a sketch.
class Design::BorderSectionTest < ActiveSupport::TestCase
  PS = Design::ParagraphStyle
  Content = Design::Views::ParagraphStyles::StylePanelContent

  setup do
    @theme = Design::Theme.create!(name: "BS #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @chapter = design_for("chapter")
    @foreword = design_for("foreword")
    @base = @theme.base_paragraph_styles.create!(
      name: "zz_box", **PS::BORDER_THICKNESS_FIELDS.index_with { 1 }.transform_keys(&:to_sym),
      **PS::BORDER_COLOR_FIELDS.index_with { "CMYK=0,0,0,100" }.transform_keys(&:to_sym),
      **PS::CORNER_FIELDS.index_with { "none" }.transform_keys(&:to_sym))
  end

  def design_for(t) = @ps.document_designs.find_by(doc_type: t) || @ps.document_designs.create!(doc_type: t)
  def content(**opts) = Nokogiri::HTML.fragment(Content.new(document_design: @foreword, style_name: "zz_box", **opts).call)
  def box(doc, name) = doc.at_css("[data-link-box='#{name}']")
  def linked(doc, group) = doc.at_css("[data-link-group='#{group}']")
  def t(key, **o) = I18n.t("design.border_controls.#{key}", **o)

  test "four matching effective values render linked; the split fields are all there, hidden by CSS" do
    doc = content
    %w[border corners].each do |b|
      assert_equal "true", box(doc, b)["data-linked"], b
      assert_equal "true", box(doc, b).at_css("[data-link-toggle='#{b}']")["aria-pressed"], b
    end
    PS::BORDER_FIELDS.each { |f| assert doc.at_css("[name='paragraph_style[#{f}]']"), f }
    split = doc.at_css("[name='paragraph_style[border_top_thickness]']").ancestors("div").map { |d| d["class"].to_s }
    assert split.any? { |c| c.include?("group-data-[linked=true]/border:hidden") }, "the split rows hide while linked"
  end

  test "each box is a labelled group" do
    doc = content
    %w[border corners].each do |b|
      assert_equal "group", box(doc, b)["role"], b
      label = doc.at_css("##{box(doc, b)['aria-labelledby']}")
      assert_equal "border-box-#{b}-label", label["id"]
      assert_equal t("boxes.#{b}"), label.text
    end
  end

  test "one side stored equal to the inherited three: linked, empty linked input, the dot says changed" do
    @foreword.paragraph_styles.create!(name: "zz_box", border_top_thickness: 1, overridden_fields: %w[border_top_thickness])
    doc = content
    assert_equal "true", box(doc, "border")["data-linked"]
    input = doc.at_css("[name='paragraph_style_link[border_thickness]']")
    assert_nil input["value"].presence
    assert_equal "1.0", input["placeholder"]
    assert_equal "changed", linked(doc, "border_thickness")["data-state"]
  end

  test "the linked controls are named paragraph_style_link[<group>] and carry their group's fields" do
    doc = content
    { "border_thickness" => PS::BORDER_THICKNESS_FIELDS, "border_color" => PS::BORDER_COLOR_FIELDS,
      "corners" => PS::CORNER_FIELDS }.each do |group, fields|
      row = linked(doc, group)
      assert_equal fields.join(" "), row["data-link-fields"]
      assert row.at_css("[name='paragraph_style_link[#{group}]']"), group
      assert row.at_css("button[data-action='design--style-autosave#revertGroup']"), group
    end
  end

  test "a different side splits the border box and the linked controls say Mixed" do
    @foreword.set_style_field!("zz_box", "border_top_thickness", "2")
    @foreword.set_style_field!("zz_box", "corner_top_left", "full")
    doc = content
    assert_equal "false", box(doc, "border")["data-linked"]
    assert_equal "false", box(doc, "corners")["data-linked"]
    assert_equal t("mixed"), doc.at_css("[name='paragraph_style_link[border_thickness]']")["placeholder"]
    corners = doc.at_css("[name='paragraph_style_link[corners]']")
    placeholder = corners.at_css("option[value=''][disabled]")
    assert_equal t("mixed"), placeholder.text
    assert placeholder.key?("selected"), "Mixed shows preselected"
    inherit = corners.css("option[value='']").reject { _1.key?("disabled") }
    assert_equal [ I18n.t("design.inputs.inherit") ], inherit.map(&:text), "a separate, choosable inherit option"
    assert_equal "changed", linked(doc, "border_thickness")["data-state"], "any user field → the group's dot"
    assert_equal "inherited", linked(doc, "border_color")["data-state"]
  end

  test "all four stored alike: the linked control shows the value" do
    @foreword.set_style_fields!("zz_box", PS::BORDER_COLOR_FIELDS.index_with { "#ff0000" })
    doc = content
    assert_equal "true", box(doc, "border")["data-linked"]
    assert_equal "#ff0000", doc.at_css("input[type=hidden][name='paragraph_style_link[border_color]']")["value"]
  end

  test "an error keyed by the group shows under the linked row with the attempted value" do
    doc = content(field_errors: { "border_thickness" => [ "bad" ] }, attempted: { "border_thickness" => "-3" })
    assert_equal "bad", linked(doc, "border_thickness").at_css("[data-field-error='border_thickness']").text
    assert_equal "-3", doc.at_css("[name='paragraph_style_link[border_thickness]']")["value"]
  end

  test "the sketch gets every field's effective value" do
    sketch = content.at_css("[data-controller~='design--box-sketch']")
    effective = JSON.parse(sketch["data-design--box-sketch-effective-value"])
    assert_equal PS::BORDER_FIELDS.sort, effective.keys.sort
    assert_equal "none", effective["corner_top_left"]
    assert content.at_css("[data-design--box-sketch-target='box']")
  end

  test "read-only: the toggles and the linked controls are disabled" do
    doc = content(editable: false)
    doc.css("[data-link-toggle]").each { |b| assert b.key?("disabled") }
    assert doc.at_css("[name='paragraph_style_link[border_thickness]']").key?("disabled")
    assert doc.at_css("[name='paragraph_style_link[corners]']").key?("disabled")
  end

  test "ids are stable across renders" do
    ids = ->(doc) { doc.css("[id]").map { _1["id"] } }
    assert_equal ids.(content), ids.(content)
  end
end
