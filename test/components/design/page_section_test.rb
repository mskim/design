require "test_helper"

class Design::PageSectionTest < ActiveSupport::TestCase
  Content = Design::Views::DocumentDesigns::PageSectionContent
  URLS = { field: "/p/field", preview: "/p/preview", paper_size: "/ps/1/edit?return_to=1" }.freeze
  FIELDS = %w[top_margin_mm bottom_margin_mm left_margin_mm right_margin_mm binding_margin_mm
              body_line_count column_count gutter].freeze

  setup do
    @theme = Design::Theme.create!(name: "PS #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "152x225", local_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "chapter")
  end

  def content(dd = @dd, **opts)
    Nokogiri::HTML.fragment(Content.new(document_design: dd, paper_size_url: URLS[:paper_size], **opts).call)
  end

  def section(dd = @dd, **opts)
    Nokogiri::HTML.fragment(Design::Views::DocumentDesigns::PageSection.new(document_design: dd, urls: URLS, **opts).call)
  end

  def input(doc, f) = doc.at_css("input[name='page[#{f}]']")
  def field(doc, f) = doc.at_css("[data-style-field='#{f}']")
  def pt(key, **o) = I18n.t("design.page_section.#{key}", **o)

  test "the section carries design--style-autosave for page[...] fields and its own morph target" do
    root = section.at_css("[data-page-section]")
    assert_equal "design--style-autosave", root["data-controller"]
    { "field-url" => "/p/field", "preview-url" => "/p/preview", "field-prefix" => "page",
      "panel-target" => "page-section-content", "required-fields" => %w[column_count gutter].to_json }.each do |k, v|
      assert_equal v, root["data-design--style-autosave-#{k}-value"], k
    end
    %w[change->design--style-autosave#fieldChanged
       turbo:before-morph-attribute->design--style-autosave#keepLocalState].each { |a| assert_includes root["data-action"].split, a }
    assert root.at_css("#page-section-content")
    status = root.at_css("[data-design--style-autosave-target='status']")
    assert status && status.ancestors("#page-section-content").empty?, "the status is outside the morphed part"
    assert_nil root.at_css("form"), "the controls belong to #page-section-form, rendered elsewhere"
  end

  test "every control is page[<field>] and belongs to #page-section-form" do
    doc = content
    assert_equal FIELDS.map { |f| "page[#{f}]" }.sort, doc.css("input[name^='page[']").map { |i| i["name"] }.sort
    assert doc.css("input[name^='page[']").all? { |i| i["form"] == "page-section-form" }
  end

  test "판형: summary and an edit link that leaves the frame; 여백: scope and binding hint" do
    doc = content
    assert_equal "신국판 152 × 225 mm", doc.at_css("[data-page-size-summary]").text
    link = doc.at_css("fieldset[data-group='page_size'] a")
    assert_equal URLS[:paper_size], link["href"]
    assert_equal "_top", link["data-turbo-frame"]
    assert_equal pt("margin_scope", size: "신국판"), doc.at_css("fieldset[data-group='margins'] [data-scope]").text
    assert_equal pt("binding_hint"), doc.at_css("[data-binding-hint]").text
    %w[page_size margins body columns].each { |g| assert doc.at_css("fieldset[data-group='#{g}']"), g }
  end

  test "margin dot: a creation-time mark equal to the rule shows none; a differing mark shows dot and ×" do
    ps = @theme.paper_sizes.create!(size_name: "X", width_mm: 152, height_mm: 225, left_margin_mm: 22, top_margin_mm: 30)
    doc = content(ps.document_designs.create!(doc_type: "chapter"))
    assert_equal "inherited", field(doc, "left_margin_mm")["data-state"]
    assert field(doc, "left_margin_mm").at_css("button[data-field='left_margin_mm'][disabled]")
    top = field(doc, "top_margin_mm")
    assert_equal "changed", top["data-state"]
    x = top.at_css("button[data-action='design--style-autosave#revert'][data-field='top_margin_mm']")
    refute x.key?("disabled")
    assert_equal pt("revert_margin", field: pt("top")), x["aria-label"]
    assert_equal "30.0", input(doc, "top_margin_mm")["value"]
  end

  test "the link toggle is pressed when Left = Right" do
    assert_equal "true", content.at_css("button[data-margin-link]")["aria-pressed"]
    assert_equal "design--style-autosave#toggleLink", content.at_css("button[data-margin-link]")["data-action"]
    @ps.update_columns(right_margin_mm: 20)
    assert_equal "false", content.at_css("button[data-margin-link]")["aria-pressed"]
  end

  test "body lines: empty with the paper size's value as placeholder; an own value shows dot and ×" do
    doc = content
    assert_nil input(doc, "body_line_count")["value"]
    assert_equal @ps.body_line_count.to_s, input(doc, "body_line_count")["placeholder"]
    assert_equal "inherited", field(doc, "body_line_count")["data-state"]
    assert_equal "#{pt('from_paper_size')}: #{@ps.body_line_count}", field(doc, "body_line_count")["title"]
    @dd.update!(body_line_count: 20)
    doc = content
    assert_equal "20", input(doc, "body_line_count")["value"]
    assert_equal "changed", field(doc, "body_line_count")["data-state"]
  end

  test "columns and gutter have no dot and no ×" do
    doc = content
    %w[column_count gutter].each do |f|
      assert doc.at_css("[data-page-field='#{f}'] input[name='page[#{f}]']"), f
      assert_nil doc.at_css("[data-style-field='#{f}']"), f
      assert_nil doc.at_css("button[data-field='#{f}']"), f
    end
    assert_equal "1", input(doc, "column_count")["value"]
    assert_equal "10.0", input(doc, "gutter")["value"]
  end

  test "a 422 re-render keeps the attempted value and shows the message under the field" do
    doc = content(field_errors: { "column_count" => [ "bad" ], "top_margin_mm" => [ "worse" ] },
                  attempted: { "column_count" => "9", "top_margin_mm" => "abc" })
    assert_equal "bad", doc.at_css("[data-field-error='column_count']").text
    assert_equal "9", input(doc, "column_count")["value"]
    assert_equal "worse", doc.at_css("[data-field-error='top_margin_mm']").text
    assert_equal "abc", input(doc, "top_margin_mm")["value"]
  end

  test "stored values that break a rule show a warning under their group" do
    @dd.update_columns(column_count: 3, gutter: 400)
    assert_equal [ I18n.t("design.page_section.errors.no_column_width") ],
                 content.css("fieldset[data-group='columns'] [data-page-warning]").map(&:text)
    @ps.update_columns(left_margin_mm: 70, right_margin_mm: 70)
    assert_includes content.css("fieldset[data-group='margins'] [data-page-warning]").map(&:text),
                    I18n.t("design.page_section.errors.too_narrow", min: 20)
  end

  test "read-only: controls and the link disabled, no active ×, no edit link" do
    @ps.update!(top_margin_mm: 30, overridden_fields: %w[top_margin_mm])
    doc = content(editable: false)
    assert doc.css("input[name^='page[']").all? { |i| i.key?("disabled") }
    assert doc.at_css("button[data-margin-link][disabled]")
    assert doc.css("button[data-action='design--style-autosave#revert']").all? { |b| b.key?("disabled") }
    assert_nil doc.at_css("fieldset[data-group='page_size'] a")
  end

  test "control ids are stable across renders (a morph keeps focus)" do
    ids = ->(doc) { doc.css("[id]").map { |e| e["id"] } }
    assert_equal ids.(content), ids.(content)
    assert_includes ids.(content), "nf-page-top_margin_mm"
  end
end
