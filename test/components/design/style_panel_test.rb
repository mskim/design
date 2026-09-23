require "test_helper"

class Design::StylePanelTest < ActiveSupport::TestCase
  URLS = { field: "/s/field", style: "/s/style", push: "/s/push", preview: "/s/preview" }.freeze
  Content = Design::Views::ParagraphStyles::StylePanelContent

  setup do
    @theme = Design::Theme.create!(name: "SP #{SecureRandom.hex(3)}", locale: "ko")
    @ps1 = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @ps2 = @theme.paper_sizes.create!(size_name: "국판", width_mm: 148, height_mm: 210)
    @chapters = [ @ps1, @ps2 ].map { |ps| design_for(ps, "chapter") }
    @forewords = [ @ps1, @ps2 ].map { |ps| design_for(ps, "foreword") }
    @chapter, @foreword = @chapters.first, @forewords.first
    @base = @theme.base_paragraph_styles.create!(name: "zz_body", font: "Base Font", font_size: 10, text_align: "left",
                                                 korean_name: "본문")
  end

  def design_for(ps, doc_type) = ps.document_designs.find_by(doc_type: doc_type) || ps.document_designs.create!(doc_type: doc_type)

  def content(dd = @foreword, name = "zz_body", **opts)
    Nokogiri::HTML.fragment(Content.new(document_design: dd, style_name: name, **opts).call)
  end

  def panel(dd = @foreword, name = "zz_body", **opts)
    c = Design::Views::ParagraphStyles::StylePanel.new(document_design: dd, style_name: name, urls: URLS,
                                                       back_url: "/back", back_frame: "properties_panel", **opts)
    c.define_singleton_method(:helpers) { Object.new.tap { |o| def o.form_authenticity_token = "t" } }
    Nokogiri::HTML.fragment(c.call)
  end

  def field(doc, f) = doc.at_css("[data-style-field='#{f}']")

  test "the sections list exactly STYLE_FIELDS, each with a control definition" do
    assert_equal Design::ParagraphStyle::STYLE_FIELDS.sort, Content::SECTIONS.values.flatten.sort
    assert_equal Design::ParagraphStyle::STYLE_FIELDS.sort, Content::FIELDS.keys.sort
  end

  test "the form carries the autosave controller and sits outside the morphed #style-panel-content" do
    doc = panel(preview_mode: "single")
    form = doc.at_css("turbo-frame#properties_panel form[data-controller='design--style-autosave']")
    assert form
    assert_equal "false", form["data-turbo"]
    assert form.at_css("#style-panel-content"), "content inside the form"
    assert_nil doc.at_css("#style-panel-content form"), "the form is not re-rendered"
    status = form.at_css("[data-design--style-autosave-target='status']")
    assert status && status.ancestors("#style-panel-content").empty?, "the status is outside the morphed part"
    { "field-url" => "/s/field", "style-url" => "/s/style", "push-url" => "/s/push", "preview-url" => "/s/preview",
      "preview-mode" => "single" }.each do |k, v|
      assert_equal v, form["data-design--style-autosave-#{k}-value"], k
    end
    %w[change->design--style-autosave#fieldChanged submit->design--style-autosave#ignoreSubmit
       turbo:before-morph-attribute->design--style-autosave#keepLocalState
       turbo:before-morph-element->design--style-autosave#keepOpenPopover].each { |a| assert_includes form["data-action"].split, a }
    assert doc.at_css("a[href='/back'][data-turbo-frame='properties_panel']")
    assert_nil doc.at_css("[name=apply_scope]"), "no save-scope control (apply-to-all is gone)"
    assert_nil doc.at_css("button[type=submit]"), "no Save button"
    refute panel.at_css("form").key?("data-design--style-autosave-preview-mode-value")
  end

  test "an inherited field is empty, with the chapter's value as placeholder and source (issue a)" do
    @chapter.paragraph_styles.create!(name: "zz_body", font_size: 11, overridden_fields: %w[font_size])
    doc = content(@foreword)
    input = doc.at_css("input[name='paragraph_style[font_size]']")
    assert_nil input["value"]
    assert_equal "11.0", input["placeholder"], "a doc type's parent is chapter's resolved style, not the theme"
    wrapper = field(doc, "font_size")
    assert_equal "inherited", wrapper["data-state"]
    assert_equal "#{I18n.t('design.style_panel.from_chapter')}: 11.0pt", wrapper["title"]
    assert_equal "#{I18n.t('design.style_panel.from_theme')}: 10.0pt", field(content(@chapters.last), "font_size")["title"]
    assert_nil field(doc, "tracking")["title"], "no parent value → no title (not a bare source label)"
  end

  test "inherited tooltips: numbers carry the control's unit; a corner preset reads as its label" do
    @base.update!(scale: 90, tracking: -0.5, space_before_in_lines: 1)
    doc = content
    from = I18n.t("design.style_panel.from_chapter")
    assert_equal "#{from}: 90.0%", field(doc, "scale")["title"]
    assert_equal "#{from}: -0.5", field(doc, "tracking")["title"], "unitless"
    assert_equal "#{from}: 1.0 #{I18n.t('design.inputs.lines')}", field(doc, "space_before_in_lines")["title"]
    @base.update!(border_top_thickness: 1.5, corner_top_left: "medium")
    doc = content
    assert_equal "#{from}: 1.5pt", field(doc, "border_top_thickness")["title"]
    assert_equal "#{from}: #{I18n.t('design.options.corner_size.medium')}", field(doc, "corner_top_left")["title"]
  end

  test "× is labelled with its field" do
    x = field(content, "font_size").at_css("button[data-action='design--style-autosave#revert']")
    assert_equal I18n.t("design.style_panel.revert_field", field: I18n.t("design.fields.size")), x["aria-label"]
  end

  test "selects are labelled: the row's label points at the select's stable id" do
    doc = content
    %w[font text_align bold_font fill_type corner_top_left].each do |f|
      select = doc.at_css("select[name='paragraph_style[#{f}]']")
      assert select["id"].present?, f
      assert_equal "sel-paragraph_style-#{f}", select["id"], f
      assert_equal 1, doc.css("label[for='#{select['id']}']").size, f
    end
  end

  test "되돌리기 counts the fields changed on any size and asks before reverting all sizes" do
    @forewords.last.paragraph_styles.create!(name: "zz_body", tracking: 1) # only on the other size
    revert = content(@foreword).at_css("button[data-action='design--style-autosave#revertStyle']")
    assert_equal I18n.t("design.style_panel.revert_all", count: 1), revert.text
    refute revert.key?("disabled"), "nothing changed on this size, but revert reaches every size"
    assert_equal I18n.t("design.style_panel.revert_confirm", count: 1), revert["data-confirm-message"]

    @foreword.set_style_field!("zz_body", "text_align", "center") # every size
    revert = content(@foreword).at_css("button[data-action='design--style-autosave#revertStyle']")
    assert_equal I18n.t("design.style_panel.revert_all", count: 2), revert.text, "union over sizes: text_align, tracking"
    assert_equal I18n.t("design.style_panel.revert_confirm", count: 2), revert["data-confirm-message"]

    assert_nil content(@chapter).at_css("button[data-action='design--style-autosave#revertStyle']")["data-confirm-message"],
               "nothing to revert → no confirm"
  end

  test "되돌리기 is disabled for a parentless style (it would vanish)" do
    @foreword.create_style!("zz_own")
    @foreword.set_style_field!("zz_own", "font_size", 12)
    assert content(@foreword, "zz_own").at_css("button[data-action='design--style-autosave#revertStyle'][disabled]")
  end

  test "read-only: the ▾ toggle is disabled" do
    assert content(editable: false).at_css("button[data-action='design--dropdown#toggle'][disabled]")
    refute content.at_css("button[data-action='design--dropdown#toggle']").key?("disabled")
  end

  test "each style field has exactly one named control" do
    doc = content
    Design::ParagraphStyle::STYLE_FIELDS.each do |f|
      assert_equal 1, doc.css("[name='paragraph_style[#{f}]']").size, f
    end
  end

  test "a changed field shows its value, a blue dot and an active ×" do
    @foreword.set_style_field!("zz_body", "font_size", 12)
    doc = content
    assert_equal "12.0", doc.at_css("input[name='paragraph_style[font_size]']")["value"]
    wrapper = field(doc, "font_size")
    assert_equal "changed", wrapper["data-state"]
    assert_includes wrapper.at_css("[data-dot]")["class"], "bg-blue-600"
    x = wrapper.at_css("button[data-action='design--style-autosave#revert'][data-field='font_size']")
    refute x.key?("disabled")
    refute_includes x["class"], "invisible"
  end

  test "generator values: dot titled 자동 크기 조정, revertible; push eligibility follows this size's marks (issue c)" do
    @chapters.first.paragraph_styles.create!(name: "zz_body", font_size: 20, overridden_fields: %w[font_size])
    @chapters.last.paragraph_styles.create!(name: "zz_body", font_size: 15, overridden_fields: [])

    on_b = content(@chapters.last)
    assert_equal "generated", field(on_b, "font_size")["data-state"]
    assert_equal I18n.t("design.style_panel.generated"), field(on_b, "font_size")["title"]
    refute field(on_b, "font_size").at_css("button[data-field='font_size']").key?("disabled")
    assert on_b.at_css("button[data-action='design--style-autosave#pushStyle'][disabled]"), "no user fields on this size"

    on_a = content(@chapters.first)
    assert_equal "changed", field(on_a, "font_size")["data-state"]
    refute on_a.at_css("button[data-action='design--style-autosave#pushStyle']").key?("disabled")
  end

  test "selects offer 상속 (<parent>) first; colours carry the parent value" do
    doc = content
    first = doc.at_css("select[name='paragraph_style[text_align]'] option")
    assert_equal I18n.t("design.inputs.inherit_with_value", value: I18n.t("design.options.text_align.left")), first.text
    assert first.key?("selected")
    assert doc.at_css("[data-controller='design--color-row'][data-design--color-row-parent-value]"),
           "text_color inherits the theme default colour"
  end

  test "sections: 글꼴 · 텍스트 always open; others open with a change and show a dot" do
    doc = content
    assert doc.at_css("details[data-section='type_text']").key?("open")
    refute doc.at_css("details[data-section='fill']").key?("open")
    assert_nil doc.at_css("details[data-section='fill'] [data-section-dot]")

    @foreword.set_style_field!("zz_body", "fill_type", "solid")
    doc = content
    assert doc.at_css("details[data-section='fill']").key?("open")
    assert doc.at_css("details[data-section='fill'] summary [data-section-dot]")
    refute doc.at_css("details[data-section='border']").key?("open")
  end

  test "chip + and ▾ menu" do
    doc = content
    assert_nil doc.at_css("[data-style-chip] [data-changed-marker]")
    assert doc.at_css("button[data-action='design--style-autosave#revertStyle'][disabled]")
    assert doc.css("[role=menu] button").last.key?("disabled"), "모든 옵션 편집… waits for D5"

    @foreword.set_style_field!("zz_body", "font_size", 12)
    doc = content
    assert_equal "+", doc.at_css("[data-style-chip] [data-changed-marker]").text
    revert = doc.at_css("button[data-action='design--style-autosave#revertStyle']")
    assert_equal I18n.t("design.style_panel.revert_all", count: 1), revert.text
    refute revert.key?("disabled")
  end

  test "push: label by doc type and a confirm naming siblings that keep their own value" do
    @foreword.set_style_field!("zz_body", "font_size", 12)
    design_for(@ps1, "prologue").set_style_field!("zz_body", "font_size", 9)
    push = content.at_css("button[data-action='design--style-autosave#pushStyle']")
    assert_equal I18n.t("design.style_panel.push_to_chapter"), push.text
    msg = push["data-confirm-message"]
    assert_includes msg, I18n.t("design.style_panel.push_confirm.chapter", count: 1)
    assert_includes msg, I18n.t("design.style_panel.push_confirm.kept", field: I18n.t("design.fields.size"), count: 1)

    @chapter.set_style_field!("zz_body", "font_size", 12)
    assert_equal I18n.t("design.style_panel.push_to_theme"),
                 content(@chapter).at_css("button[data-action='design--style-autosave#pushStyle']").text
  end

  test "scope text; name and Korean name are read-only" do
    doc = content
    assert_equal "#{I18n.t('design.doc_types.foreword')} · #{I18n.t('design.style_panel.all_sizes')}", doc.at_css("[data-scope]").text
    assert_equal "zz_body", doc.at_css("[data-style-name]").text
    assert_equal "본문", doc.at_css("[data-korean-name]").text
    assert_nil doc.at_css("[name='paragraph_style[name]'], [name='paragraph_style[korean_name]'], [name='paragraph_style[vertical_align]']")
  end

  test "a field error shows under the field with the attempted value; a panel error shows at the top" do
    doc = content(field_errors: { "font_size" => [ "not a number" ] }, attempted: { "font_size" => "abc" })
    assert_equal "not a number", field(doc, "font_size").at_css("[data-field-error='font_size']").text
    assert_equal "abc", doc.at_css("input[name='paragraph_style[font_size]']")["value"]
    assert_equal "no chapter", content(error: "no chapter").at_css("#style-panel-content > [role=alert]").text
  end

  test "read-only: controls disabled, no active ×" do
    @foreword.set_style_field!("zz_body", "font_size", 12)
    doc = content(editable: false)
    assert doc.at_css("input[name='paragraph_style[font_size]'][disabled]")
    assert doc.at_css("select[name='paragraph_style[text_align]'][disabled]")
    assert doc.css("button[data-action='design--style-autosave#revert']").all? { |b| b.key?("disabled") }
  end

  test "control ids are stable across inherited, changed and 422 renders (so a morph keeps focus), and unique" do
    ids = ->(doc) { doc.css("[id]").map { |e| e["id"] } }
    inherited = ids.(content)
    assert_equal inherited.uniq, inherited, "ids are unique within a render"
    assert_equal inherited, ids.(content)

    { "font_size" => 12, "text_align" => "center", "text_color" => "CMYK=0,0,0,50", "border_top_thickness" => "1.0",
      "font" => Design::Theme::AVAILABLE_FONTS.first, "fill_type" => "solid" }.each do |f, v|
      @foreword.set_style_field!("zz_body", f, v)
    end
    assert_equal inherited, ids.(content), "changed render"
    assert_equal inherited, ids.(content(field_errors: { "font_size" => [ "bad" ], "text_align" => [ "bad" ] },
                                         attempted: { "font_size" => "abc", "text_align" => "banana" })), "422 render"
  end
end
