require "test_helper"

# D2b endpoints: a doc type's style, keyed by name, edited field by field on
# every paper size of the doc type.
class Design::DocumentDesignStylesTest < ActionDispatch::IntegrationTest
  STREAM = { "Accept" => "text/vnd.turbo-stream.html" }.freeze
  FRAME = { "Turbo-Frame" => "properties_panel" }.freeze

  setup do
    sign_in :david
    @theme = Design::Theme.create!(name: "DS #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @ps2 = @theme.paper_sizes.create!(size_name: "국판", width_mm: 148, height_mm: 210)
    @chapters = [ @ps, @ps2 ].map { |ps| design_for(ps, "chapter") }
    @forewords = [ @ps, @ps2 ].map { |ps| design_for(ps, "foreword") }
    @fw = @forewords.first
    @base = @theme.base_paragraph_styles.create!(name: "zz_body", font: "Base Font", font_size: 10, text_align: "left")
  end

  def design_for(ps, doc_type) = ps.document_designs.find_by(doc_type: doc_type) || ps.document_designs.create!(doc_type: doc_type)
  def row_of(dd, name = "zz_body") = dd.paragraph_styles.find_by(name: name)
  def style_path(dd = @fw, name = "zz_body", **q) = design.theme_paper_size_document_design_style_path(dd.theme, dd.paper_size, dd, name, **q)
  def field_path(dd = @fw, name = "zz_body") = design.field_theme_paper_size_document_design_style_path(dd.theme, dd.paper_size, dd, name)
  def push_path(dd = @fw, name = "zz_body") = design.push_theme_paper_size_document_design_style_path(dd.theme, dd.paper_size, dd, name)

  def stub_preview(pages: 1)
    fake = Object.new
    fake.define_singleton_method(:generate) do
      { success: true, page_width: 432.0, page_height: 648.0, error: nil,
        pages: Array.new(pages) { |i| { jpg_path: "/tmp/p#{i}.jpg", overlay_data: [] } } }
    end
    original = Design::PreviewService.method(:new)
    Design::PreviewService.define_singleton_method(:new) { |*, **| fake }
    yield
  ensure
    Design::PreviewService.define_singleton_method(:new, original) if original
  end

  # Number of theme .db exports during the block (export! itself is stubbed).
  def count_exports
    count = 0
    original = Design::ThemeDbExportService.method(:new)
    Design::ThemeDbExportService.define_singleton_method(:new) do |*args, **kw|
      original.call(*args, **kw).tap { |svc| svc.define_singleton_method(:export!) { count += 1 } }
    end
    yield
    count
  ensure
    Design::ThemeDbExportService.define_singleton_method(:new, original) if original
  end

  def stream_attrs = response.body.scan(/<turbo-stream([^>]*)>/).map { |(a)| a.scan(/([\w-]+)="([^"]*)"/).to_h }

  def stream_template(target)
    html = response.body[%r{<turbo-stream[^>]*target="#{target}"[^>]*><template>(.*?)</template></turbo-stream>}m, 1]
    assert html, "no #{target} stream"
    Nokogiri::HTML5.fragment(html)
  end

  # ── GET ──

  test "GET in the properties_panel frame renders the embedded panel, Back to the 단락정의 list" do
    get style_path, headers: FRAME
    assert_response :success
    assert_select "turbo-frame#properties_panel form[data-controller~='design--style-autosave'] #style-panel-content"
    assert_select "turbo-frame#preview_frame", count: 0
    assert_select "a[data-turbo-frame='properties_panel'][href*='tab=typography']"
  end

  test "GET as a full page renders the editor page with a single-page preview" do
    get style_path
    assert_response :success
    assert_select "turbo-frame#preview_frame[src*='preview_mode=single']"
    assert_select "form[data-design--style-autosave-preview-mode-value='single']"
    assert_select "form[data-design--style-autosave-preview-url-value*='preview_mode=single']"
    assert_select "a[data-turbo-frame='_top'][href*='tab=typography']"
    assert_select "aside option[data-url=?]", style_path(@forewords.last), { count: 1 }, "switching size opens this style there"
  end

  test "GET shows a doc type's parent values, not the theme's (issue a)" do
    @chapters.first.paragraph_styles.create!(name: "zz_body", font_size: 11, overridden_fields: %w[font_size])
    get style_path, headers: FRAME
    assert_select "input[name='paragraph_style[font_size]'][placeholder='11.0']"
  end

  test "GET for a name no layer defines falls back to the document view" do
    get style_path(@fw, "zz_nowhere")
    assert_redirected_to design.edit_theme_paper_size_document_design_path(@theme, @ps, @fw)
    get style_path(@fw, "zz_nowhere"), headers: FRAME
    assert_response :success
    assert_select "turbo-frame#properties_panel form[data-controller~='design--live-preview']"
  end

  # ── PATCH / DELETE field ──

  test "PATCH field writes this doc type on every size and answers with a morph + preview" do
    exports = count_exports do
      stub_preview { patch field_path, params: { field: "font_size", value: "12" }, headers: STREAM }
    end
    assert_response :success
    @forewords.each { |dd| assert_equal 12, row_of(dd).font_size.to_i }
    @chapters.each { |dd| assert_nil row_of(dd), "chapter untouched" }
    assert_includes stream_attrs, { "method" => "morph", "action" => "replace", "target" => "style-panel-content" }
    assert stream_attrs.any? { |a| a["target"] == "preview_frame" }
    assert stream_template("style-panel-content").at_css("div#style-panel-content"), "the template root is the target"
    refute_includes response.body, "<html", "components stream without the layout"
    refute_includes response.body, "<title"
    assert_equal 1, exports
  end

  test "render_preview=0 skips the preview stream" do
    patch field_path, params: { field: "text_align", value: "center", render_preview: "0" }, headers: STREAM
    assert_response :success
    refute stream_attrs.any? { |a| a["target"] == "preview_frame" }
    assert_equal "center", row_of(@fw).text_align
  end

  test "preview_mode=single re-renders a one-page preview" do
    stub_preview(pages: 3) do
      patch field_path, params: { field: "text_align", value: "center", preview_mode: "single" }, headers: STREAM
    end
    assert_equal 1, stream_template("preview_frame").css("img").size
  end

  test "a blank PATCH and a DELETE both revert the field on every size" do
    @fw.set_style_field!("zz_body", "text_align", "center")
    stub_preview { patch field_path, params: { field: "text_align", value: "" }, headers: STREAM }
    @forewords.each { |dd| assert_nil row_of(dd) }

    @fw.set_style_field!("zz_body", "text_align", "center")
    stub_preview { delete field_path, params: { field: "text_align" }, headers: STREAM }
    assert_response :success
    @forewords.each { |dd| assert_nil row_of(dd) }
  end

  test "a field outside STYLE_FIELDS is a 400 and writes nothing" do
    %w[name korean_name vertical_align overridden_fields bogus].each do |f|
      exports = count_exports { patch field_path, params: { field: f, value: "x" }, headers: STREAM }
      assert_response :bad_request, f
      assert_equal 0, exports, f
    end
    delete field_path, params: { field: "name" }, headers: STREAM
    assert_response :bad_request
    assert_nil row_of(@fw)
  end

  test "an invalid value is a 422: message under the field, attempted value kept, nothing written" do
    exports = count_exports do
      stub_preview { patch field_path, params: { field: "font_size", value: "abc" }, headers: STREAM }
    end
    assert_response :unprocessable_entity
    tpl = stream_template("style-panel-content")
    assert_equal I18n.t("design.style_panel.errors.not_a_number"), tpl.at_css("[data-field-error='font_size']").text.strip
    assert_equal "abc", tpl.at_css("input[name='paragraph_style[font_size]']")["value"]
    assert stream_attrs.any? { |a| a["target"] == "preview_frame" }, "earlier saves may have skipped the preview"
    assert_nil row_of(@fw)
    assert_equal 0, exports
  end

  test "a write to a name no layer defines is a 404" do
    patch field_path(@fw, "zz_nowhere"), params: { field: "font_size", value: "12" }, headers: STREAM
    assert_response :not_found
    assert_nil row_of(@fw, "zz_nowhere")
    delete field_path(@fw, "zz_nowhere"), params: { field: "font_size" }, headers: STREAM
    assert_response :not_found
    delete style_path(@fw, "zz_nowhere"), headers: STREAM
    assert_response :not_found
    post push_path(@fw, "zz_nowhere"), headers: STREAM
    assert_response :not_found
  end

  test "a value that isn't a string (value[]=, value[a]=) is a 400 and writes nothing" do
    exports = count_exports do
      patch field_path, params: "field=font_size&value[]=12", headers: STREAM
      assert_response :bad_request
      patch field_path, params: "field=text_align&value[a]=1", headers: STREAM
      assert_response :bad_request
    end
    assert_equal 0, exports
    assert_nil row_of(@fw)
  end

  test "a select value outside the panel's options is a 422; a listed one saves" do
    exports = count_exports do
      stub_preview { patch field_path, params: { field: "text_align", value: "banana" }, headers: STREAM }
    end
    assert_response :unprocessable_entity
    assert_equal I18n.t("design.style_panel.errors.invalid_option"),
                 stream_template("style-panel-content").at_css("[data-field-error='text_align']").text.strip
    assert_nil row_of(@fw)
    assert_equal 0, exports

    stub_preview { patch field_path, params: { field: "text_align", value: "justify" }, headers: STREAM }
    assert_response :success
    @forewords.each { |dd| assert_equal "justify", row_of(dd).text_align }
  end

  test "an infinite or huge number is a 422" do
    %w[1e999 99999].each do |v|
      stub_preview { patch field_path, params: { field: "font_size", value: v }, headers: STREAM }
      assert_response :unprocessable_entity, v
    end
    assert_nil row_of(@fw)
  end

  test "a 422 on an existing row leaves its stored values alone" do
    @fw.set_style_field!("zz_body", "font_size", 12)
    stub_preview { patch field_path, params: { field: "font_size", value: "abc" }, headers: STREAM }
    assert_response :unprocessable_entity
    assert_equal "abc", stream_template("style-panel-content").at_css("input[name='paragraph_style[font_size]']")["value"]
    @forewords.each { |dd| assert_equal 12, row_of(dd).reload.font_size.to_i }
  end

  test "render_preview=0 skips the preview on a 422, DELETE field, DELETE style and push" do
    requests = {
      "422" => -> { patch field_path, params: { field: "font_size", value: "abc", render_preview: "0" }, headers: STREAM },
      "DELETE field" => -> { delete field_path, params: { field: "text_align", render_preview: "0" }, headers: STREAM },
      "DELETE style" => -> { delete style_path, params: { render_preview: "0" }, headers: STREAM },
      "push" => -> { post push_path, params: { render_preview: "0" }, headers: STREAM }
    }
    requests.each do |label, request|
      @fw.set_style_field!("zz_body", "text_align", "center")
      request.call
      assert_includes [ 200, 422 ], response.status, label
      assert stream_attrs.any? { |a| a["target"] == "style-panel-content" }, label
      refute stream_attrs.any? { |a| a["target"] == "preview_frame" }, label
    end
  end

  test "names with dots and Korean names route" do
    @theme.base_paragraph_styles.create!(name: "cover.title", font_size: 20)
    @theme.base_paragraph_styles.create!(name: "본문", font_size: 10)
    [ "cover.title", "본문" ].each do |name|
      get style_path(@fw, name), headers: FRAME
      assert_response :success, name
      assert_select "[data-style-name]", text: name
      patch field_path(@fw, name), params: { field: "text_align", value: "center", render_preview: "0" }, headers: STREAM
      assert_response :success, name
      assert_equal "center", row_of(@fw, name).text_align, name
    end
  end

  # ── D5 link groups ──

  test "PATCH values[...] writes a whole group in one request" do
    values = Design::ParagraphStyle::BORDER_COLOR_FIELDS.index_with { "#ff0000" }
    exports = count_exports { stub_preview { patch field_path, params: { values: values }, headers: STREAM } }
    assert_response :success
    assert_equal 1, exports
    Design::ParagraphStyle::BORDER_COLOR_FIELDS.each { |f| assert_equal "#ff0000", row_of(@fw)[f], f }
    assert_includes stream_attrs, { "method" => "morph", "action" => "replace", "target" => "style-panel-content" }
  end

  test "DELETE fields[] reverts a whole group in one request" do
    @fw.set_style_fields!("zz_body", Design::ParagraphStyle::CORNER_FIELDS.index_with { "full" })
    stub_preview { delete field_path, params: { fields: Design::ParagraphStyle::CORNER_FIELDS }, headers: STREAM }
    assert_response :success
    assert(Design::ParagraphStyle::CORNER_FIELDS.all? { |f| row_of(@fw).nil? || row_of(@fw)[f].nil? })
  end

  test "400: a values set or a fields list that isn't exactly one group" do
    [ Design::ParagraphStyle::CORNER_FIELDS.first(3).index_with { "full" },
      Design::ParagraphStyle::CORNER_FIELDS.index_with { "full" }.merge("font" => "x"),
      Design::ParagraphStyle::CORNER_FIELDS.index_with { [ "full" ] } ].each do |values|
      patch field_path, params: { values: values }, headers: STREAM
      assert_response :bad_request, values.inspect
    end
    patch field_path, params: { values: "full" }, headers: STREAM
    assert_response :bad_request
    delete field_path, params: { fields: %w[corner_top_left] }, headers: STREAM
    assert_response :bad_request
    delete field_path, params: { fields: "corner_top_left" }, headers: STREAM
    assert_response :bad_request
  end

  test "422 for a group: nothing written, one message under the linked row, the attempt kept" do
    values = Design::ParagraphStyle::BORDER_THICKNESS_FIELDS.index_with { "-3" }
    stub_preview { patch field_path, params: { values: values }, headers: STREAM }
    assert_response :unprocessable_entity
    tpl = stream_template("style-panel-content")
    assert tpl.at_css("[data-field-error='border_thickness']"), "keyed by the group"
    assert_equal "-3", tpl.at_css("[name='paragraph_style_link[border_thickness]']")["value"]
    assert(row_of(@fw).nil? || row_of(@fw).border_top_thickness.nil?)
  end

  # ── DELETE style / POST push ──

  test "DELETE style reverts every field on every size" do
    @fw.set_style_field!("zz_body", "text_align", "center")
    stub_preview { delete style_path, headers: STREAM }
    assert_response :success
    @forewords.each { |dd| assert_nil row_of(dd) }
  end

  test "push from a doc type moves its user fields to chapter on every size" do
    @fw.set_style_field!("zz_body", "text_align", "center")
    stub_preview { post push_path, headers: STREAM }
    assert_response :success
    @chapters.each { |ch| assert_equal "center", row_of(ch).text_align }
    @forewords.each { |dd| assert_nil row_of(dd) }
  end

  test "push from chapter moves its user fields to the theme base" do
    @chapters.first.set_style_field!("zz_body", "text_align", "center")
    stub_preview { post push_path(@chapters.first), headers: STREAM }
    assert_equal "center", @base.reload.text_align
    @chapters.each { |ch| assert_nil row_of(ch) }
  end

  test "push with a size missing its chapter is a 422 with the message, nothing written" do
    @fw.set_style_field!("zz_body", "text_align", "center")
    @chapters.last.destroy!
    exports = count_exports { stub_preview { post push_path, headers: STREAM } }
    assert_response :unprocessable_entity
    assert_equal I18n.t("design.style_panel.errors.missing_chapter", sizes: @ps2.display_name),
                 stream_template("style-panel-content").at_css("[role=alert]").text
    assert_equal "center", row_of(@fw).text_align
    assert_nil row_of(@chapters.first)
    assert_equal 0, exports
  end

  # ── access ──

  test "a read-only (system) theme is 403 on every endpoint" do
    theme = Design::Theme.create!(name: "Sys #{SecureRandom.hex(3)}", locale: "ko", user_id: nil)
    ps = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = design_for(ps, "foreword")
    theme.base_paragraph_styles.create!(name: "zz_body", font_size: 10)
    get style_path(dd)
    assert_response :forbidden
    patch field_path(dd), params: { field: "font_size", value: "12" }
    assert_response :forbidden
    delete field_path(dd), params: { field: "font_size" }
    assert_response :forbidden
    delete style_path(dd)
    assert_response :forbidden
    post push_path(dd)
    assert_response :forbidden
    get design.new_theme_paper_size_document_design_style_path(theme, ps, dd), headers: FRAME
    assert_response :forbidden
    post styles_path(dd), params: { name: "zz_new" }, headers: STREAM
    assert_response :forbidden
    assert_nil row_of(dd)
    assert_nil row_of(dd, "zz_new")
  end

  # ── 새 스타일 ──

  def styles_path(dd = @fw) = design.theme_paper_size_document_design_styles_path(dd.theme, dd.paper_size, dd)

  test "GET new renders the 새 스타일 form in the frame" do
    get design.new_theme_paper_size_document_design_style_path(@theme, @ps, @fw), headers: FRAME
    assert_response :success
    assert_select "turbo-frame#properties_panel form[action=?] input[name=name]", styles_path
    assert_select "input[name=korean_name]"
  end

  test "create makes a parentless style on every size of the doc type and answers with its panel" do
    exports = count_exports { post styles_path, params: { name: "zz_new", korean_name: "새것" }, headers: STREAM }
    assert_response :success
    @forewords.each do |dd|
      row = row_of(dd, "zz_new")
      assert row, "row on #{dd.paper_size.size_name}"
      assert_equal "새것", row.korean_name
      assert Design::ParagraphStyle::STYLE_FIELDS.all? { |f| row[f].nil? }
    end
    @chapters.each { |dd| assert_nil row_of(dd, "zz_new") }
    assert_includes stream_attrs, { "action" => "replace", "target" => "properties_panel" }
    assert stream_template("properties_panel").at_css("form[data-controller~='design--style-autosave']")
    assert_equal 1, exports
  end

  test "create with an existing name opens that style and creates nothing" do
    exports = count_exports { post styles_path, params: { name: "zz_body" }, headers: STREAM }
    assert_response :success
    assert_nil row_of(@fw)
    assert_equal 0, exports
  end

  test "create rejects a blank, reserved or slash name with 422" do
    [ "", "  ", "new", "a/b" ].each do |name|
      post styles_path, params: { name: name }, headers: STREAM
      assert_response :unprocessable_entity, name.inspect
      assert stream_template("properties_panel").at_css("[role=alert]"), name.inspect
    end
  end
end
