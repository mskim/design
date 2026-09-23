require "test_helper"

class Design::ObjectSectionTest < ActiveSupport::TestCase
  Content = Design::Views::DocumentDesigns::ObjectSectionContent
  Section = Design::Views::DocumentDesigns::ObjectSection
  URLS = { field: "/o/field", preview: "/o/preview" }.freeze

  setup do
    @theme = Design::Theme.create!(name: "OS #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @copyright = @ps.document_designs.create!(doc_type: "copyright")
    @wing = @ps.document_designs.create!(doc_type: "front_wing")
  end

  def content(dd = @copyright, **opts) = Nokogiri::HTML.fragment(Content.new(document_design: dd, **opts).call)
  def section(dd = @copyright, **opts) = Nokogiri::HTML.fragment(Section.new(document_design: dd, urls: URLS, **opts).call)
  def input(doc, f) = doc.at_css("[name='object[#{f}]']")
  def field(doc, f) = doc.at_css("[data-style-field='#{f}']")
  def txt(key, **o) = I18n.t("design.object_section.#{key}", **o)

  test "the section carries design--style-autosave for object[...] fields and its own morph target" do
    root = section.at_css("[data-object-section]")
    assert_equal "design--style-autosave", root["data-controller"]
    { "field-url" => "/o/field", "preview-url" => "/o/preview", "field-prefix" => "object",
      "panel-target" => "object-section-content" }.each do |key, value|
      assert_equal value, root["data-design--style-autosave-#{key}-value"], key
    end
    assert_nil root["data-design--style-autosave-required-fields-value"], "nothing here is required"
    %w[change->design--style-autosave#fieldChanged
       turbo:before-morph-attribute->design--style-autosave#keepLocalState
       turbo:before-morph-element->design--style-autosave#keepOpenPopover].each do |a|
      assert_includes root["data-action"].split, a
    end
    assert root.at_css("#object-section-content")
    status = root.at_css("[data-design--style-autosave-target='status']")
    assert status && status.ancestors("#object-section-content").empty?, "the status is outside the morphed part"
    assert_nil root.at_css("form"), "the controls belong to #object-section-form, rendered elsewhere"
  end

  test "copyright: the text box inspector only, every control in #object-section-form" do
    doc = content
    assert doc.at_css("fieldset[data-group='space']")
    assert_equal Design::DocumentDesign::OBJECT_TEXT_BOX_FIELDS.sort,
                 doc.css("[name^='object[']").map { |e| e["name"][/\[(.+)\]/, 1] }.sort
    assert doc.css("[name^='object[']").all? { |e| e["form"] == "object-section-form" }
    assert_equal txt("text_box_hint"), doc.at_css("[data-object-hint]").text
  end

  test "copyright: the anchor grid shows the inherited default pressed and offers a revert" do
    doc = content
    assert_equal "7", input(doc, "text_box_anchor_position")["value"]
    assert_equal "true", doc.at_css("button[data-anchor='7']")["aria-pressed"]
    assert_equal "inherited", field(doc, "text_box_anchor_position")["data-state"]
    assert_equal "#{txt('default')}: #{txt('anchors.a7')}", field(doc, "text_box_anchor_position")["title"]
    assert field(doc, "text_box_anchor_position").at_css("button[data-field='text_box_anchor_position'][disabled]")
    @copyright.update!(text_box_anchor_position: 5)
    doc = content
    assert_equal "changed", field(doc, "text_box_anchor_position")["data-state"]
    assert_equal "true", doc.at_css("button[data-anchor='5']")["aria-pressed"]
    x = field(doc, "text_box_anchor_position").at_css("button[data-action='design--style-autosave#revert']")
    refute x.key?("disabled")
    assert_equal txt("revert_field", field: txt("position")), x["aria-label"]
  end

  test "copyright: each cell size is written with its partner; the anchor saves alone" do
    doc = content
    assert_equal "text_box_grid_height", input(doc, "text_box_grid_width")["data-joint-with"]
    assert_equal "text_box_grid_width", input(doc, "text_box_grid_height")["data-joint-with"]
    assert_nil input(doc, "text_box_anchor_position")["data-joint-with"],
               "the engine defaults each field on its own, so an anchor needs no sizes with it"
  end

  test "copyright: the cell fields show the effective size, bounded by the page's grid" do
    doc = content
    assert_equal "4", input(doc, "text_box_grid_width")["value"]
    assert_equal "6", input(doc, "text_box_grid_height")["value"]
    assert_equal "6", scrub(doc, "text_box_grid_width")["data-design--scrub-input-max-value"]
    assert_equal "12", scrub(doc, "text_box_grid_height")["data-design--scrub-input-max-value"]
    assert_equal "inherited", field(doc, "text_box_grid_width")["data-state"]
    @copyright.update!(text_box_grid_width: 2)
    assert_equal "changed", field(content, "text_box_grid_width")["data-state"]
  end

  test "a landscape page turns the grid, its limits and the sketch around" do
    ps = @theme.paper_sizes.create!(size_name: "가로", width_mm: 297, height_mm: 210)
    doc = content(ps.document_designs.create!(doc_type: "copyright"))
    assert_equal "12", scrub(doc, "text_box_grid_width")["data-design--scrub-input-max-value"]
    assert_equal "6", scrub(doc, "text_box_grid_height")["data-design--scrub-input-max-value"]
    group = doc.at_css("[data-controller='design--cell-grid']")
    assert_equal "12", group["data-design--cell-grid-columns-value"]
    assert_equal "6", group["data-design--cell-grid-rows-value"]
    assert_includes doc.at_css("[data-design--cell-grid-target='grid']")["style"], "aspect-ratio: 12 / 6"
  end

  test "the mini grid's group wires the anchor and both size fields to design--cell-grid" do
    doc = content
    group = doc.at_css("[data-controller='design--cell-grid']")
    %w[change->design--cell-grid#draw input->design--cell-grid#draw
       turbo:morph-element->design--cell-grid#draw].each { |a| assert_includes group["data-action"].split, a }
    assert_equal "anchorInput", input(doc, "text_box_anchor_position")["data-design--cell-grid-target"]
    assert_equal "widthInput", input(doc, "text_box_grid_width")["data-design--cell-grid-target"]
    assert_equal "heightInput", input(doc, "text_box_grid_height")["data-design--cell-grid-target"]
    assert group.at_css("[data-design--cell-grid-target='box']")
    assert group.at_css("[data-design--cell-grid-target='handle']"), "copyright's box is draggable"
  end

  test "front_wing: the photo inspector only — size sketch, crop point, fit, border" do
    doc = content(@wing)
    assert_equal Design::DocumentDesign::OBJECT_PHOTO_FIELDS.sort,
                 doc.css("[name^='object[']").map { |e| e["name"][/\[(.+)\]/, 1] }.sort
    assert_equal "photo_grid_height", input(doc, "photo_grid_width")["data-joint-with"]
    assert_nil input(doc, "photo_anchor")["data-joint-with"], "the crop point is independent of the size"
    assert_nil doc.at_css("[data-design--cell-grid-target='handle']"), "the sketch is not draggable"
    assert_equal txt("photo_sketch_hint"), doc.at_css("[data-cell-grid-hint]").text
    crop = doc.at_css("[data-controller='design--anchor-grid'][data-crop='true']")
    assert crop
    assert_equal txt("crop"), crop.at_css("[role=group]")["aria-label"]
    assert_equal txt("crop_hint"), doc.at_css("[data-crop-hint]").text
    fit = input(doc, "photo_fit")
    assert_equal "select", fit.name
    assert_equal txt("fit_hint"), fit["title"]
    assert_equal %w[cover contain], fit.css("option").map { |o| o["value"] }
    assert_equal I18n.t("design.options.photo_fit.cover"), fit.at_css("option[selected]").text
    assert doc.at_css("[data-controller='design--color-row'] input[type=hidden][name='object[photo_border_color]']")
  end

  test "front_wing: a photo field's dot compares against the column default" do
    doc = content(@wing)
    %w[photo_grid_width photo_grid_height photo_anchor photo_fit photo_border_width photo_border_color].each do |f|
      assert_equal "inherited", field(doc, f)["data-state"], f
    end
    assert_equal "3", input(doc, "photo_grid_width")["value"]
    assert_equal "2", input(doc, "photo_anchor")["value"], "the column default is 2 after the D4 swap"
    @wing.update!(photo_grid_width: 4, photo_fit: "contain")
    doc = content(@wing)
    assert_equal "changed", field(doc, "photo_grid_width")["data-state"]
    assert_equal "changed", field(doc, "photo_fit")["data-state"]
    assert_equal "inherited", field(doc, "photo_grid_height")["data-state"]
  end

  test "a doc type with no inspector renders nothing at all" do
    chapter = @ps.document_designs.create!(doc_type: "chapter")
    assert_empty content(chapter).to_html.strip
    assert_empty section(chapter).to_html.strip
  end

  test "a 422 re-render keeps the attempted value and shows the message under the field" do
    doc = content(field_errors: { "text_box_grid_width" => [ "bad" ] }, attempted: { "text_box_grid_width" => "9" })
    assert_equal "bad", doc.at_css("[data-field-error='text_box_grid_width']").text
    assert_equal "9", input(doc, "text_box_grid_width")["value"]
    assert_equal "6", input(doc, "text_box_grid_height")["value"], "the other fields show stored values"
  end

  test "read-only: every control disabled, no active × and no handle" do
    doc = content(editable: false)
    assert doc.css("[name^='object[']").all? { |e| e.key?("disabled") }
    assert doc.css("button[data-anchor]").all? { |b| b.key?("disabled") }
    assert doc.css("button[data-action='design--style-autosave#revert']").all? { |b| b.key?("disabled") }
    assert_nil doc.at_css("[data-design--cell-grid-target='handle']")
  end

  test "control ids are stable across renders (a morph keeps focus)" do
    ids = ->(doc) { doc.css("[id]").map { |e| e["id"] } }
    assert_equal ids.(content), ids.(content)
    assert_includes ids.(content), "nf-object-text_box_grid_width"
  end

  private

  def scrub(doc, field) = input(doc, field).ancestors("[data-controller='design--scrub-input']").first
end
