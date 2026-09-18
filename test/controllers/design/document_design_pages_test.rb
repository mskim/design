require "test_helper"

# D3 Page section endpoints: margins on the paper size (every doc type on it),
# body lines / columns / gutter on this design; one field, or the linked
# Left/Right pair, per request.
class Design::DocumentDesignPagesTest < ActionDispatch::IntegrationTest
  STREAM = { "Accept" => "text/vnd.turbo-stream.html" }.freeze

  setup do
    sign_in :david
    @theme = Design::Theme.create!(name: "PG #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @chapter = @ps.document_designs.create!(doc_type: "chapter")
    @poem = @ps.document_designs.create!(doc_type: "poem")
  end

  def field_path(dd = @chapter) = design.field_theme_paper_size_document_design_page_path(@theme, @ps, dd)

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

  # Like stub_preview, but yields each PreviewService.new's keywords to `on_new`
  # at call time (before the request's later writes, if any).
  def stub_preview_capturing(on_new)
    fake = Object.new
    fake.define_singleton_method(:generate) do
      { success: true, page_width: 432.0, page_height: 648.0, error: nil, pages: [ { jpg_path: "/tmp/p0.jpg", overlay_data: [] } ] }
    end
    original = Design::PreviewService.method(:new)
    Design::PreviewService.define_singleton_method(:new) { |*, **kw| on_new.call(kw); fake }
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

  test "PATCH a margin writes it on the paper size, marks it, and answers with a morph + preview" do
    exports = count_exports { stub_preview { patch field_path, params: { field: "top_margin_mm", value: "20" }, headers: STREAM } }
    assert_response :success
    @ps.reload
    assert_equal 20, @ps.top_margin_mm.to_i
    assert @ps.overridden?(:top_margin_mm)
    assert_equal 1, exports
    assert_includes stream_attrs, { "method" => "morph", "action" => "replace", "target" => "page-section-content" }
    assert stream_attrs.any? { |a| a["target"] == "preview_frame" }
    tpl = stream_template("page-section-content")
    assert tpl.at_css("div#page-section-content"), "the template root is the target"
    assert_equal "20.0", tpl.at_css("input[name='page[top_margin_mm]']")["value"]
    refute_includes response.body, "<html"
  end

  test "a margin edit invalidates every doc type's preview on the size (paper_size.updated_at)" do
    @ps.update_columns(updated_at: 1.day.ago)
    stub_preview { patch field_path(@poem), params: { field: "bottom_margin_mm", value: "30" }, headers: STREAM }
    assert_operator @ps.reload.updated_at, :>, 1.minute.ago
  end

  test "404 when the design is on another paper size than the path's" do
    other = @theme.paper_sizes.create!(size_name: "국판", width_mm: 148, height_mm: 210).document_designs.create!(doc_type: "chapter")
    path = design.field_theme_paper_size_document_design_page_path(@theme, @ps, other)
    exports = count_exports do
      patch path, params: { field: "top_margin_mm", value: "20" }, headers: STREAM
      assert_response :not_found
      delete path, params: { field: "top_margin_mm" }, headers: STREAM
      assert_response :not_found
    end
    assert_equal 0, exports
    assert_equal 18, @ps.reload.top_margin_mm.to_i
  end

  test "PATCH a design field writes it on this design only" do
    stub_preview { patch field_path, params: { field: "column_count", value: "2" }, headers: STREAM }
    assert_response :success
    assert_equal 2, @chapter.reload.column_count
    assert_equal 1, @poem.reload.column_count
    stub_preview { patch field_path, params: { field: "body_line_count", value: "20" }, headers: STREAM }
    assert_equal 20, @chapter.reload[:body_line_count]
  end

  test "the linked pair sets Left and Right in one request, both marked" do
    stub_preview { patch field_path, params: { values: { left_margin_mm: "18", right_margin_mm: "18" } }, headers: STREAM }
    assert_response :success
    @ps.reload
    assert_equal [ 18, 18 ], [ @ps.left_margin_mm.to_i, @ps.right_margin_mm.to_i ]
    assert @ps.overridden?(:left_margin_mm) && @ps.overridden?(:right_margin_mm)
  end

  test "400: unknown field, non-String value, bad values keys, revert of column_count / gutter" do
    [ { field: "width_mm", value: "1" }, { field: "bogus", value: "1" }, { field: "top_margin_mm", value: [ "1" ] },
      { field: "top_margin_mm" }, { values: { left_margin_mm: "18", top_margin_mm: "18" } },
      { values: { left_margin_mm: [ "18" ] } }, { values: "18" } ].each do |params|
      exports = count_exports { patch field_path, params: params, headers: STREAM }
      assert_response :bad_request, params.inspect
      assert_equal 0, exports
    end
    %w[column_count gutter bogus].each do |f|
      delete field_path, params: { field: f }, headers: STREAM
      assert_response :bad_request, f
    end
    assert_equal 18, @ps.reload.top_margin_mm.to_i
  end

  test "422: the attempted value and message are shown, nothing is written" do
    exports = count_exports do
      stub_preview { patch field_path, params: { field: "top_margin_mm", value: "abc" }, headers: STREAM }
    end
    assert_response :unprocessable_entity
    tpl = stream_template("page-section-content")
    assert_equal I18n.t("design.page_section.errors.not_a_number"), tpl.at_css("[data-field-error='top_margin_mm']").text
    assert_equal "abc", tpl.at_css("input[name='page[top_margin_mm]']")["value"]
    assert_equal "22.0", tpl.at_css("input[name='page[left_margin_mm]']")["value"], "the other fields show stored values"
    assert stream_attrs.any? { |a| a["target"] == "preview_frame" }, "a 422 still refreshes the preview"
    @ps.reload
    assert_equal 18, @ps.top_margin_mm.to_i
    refute @ps.overridden?(:top_margin_mm)
    assert_equal 0, exports
  end

  test "422 for a design field: column_count out of range, body_line_count not above the heading" do
    assert_equal 6, @chapter.heading_height_in_lines
    { "column_count" => [ "7", I18n.t("design.page_section.errors.out_of_range", min: 1, max: Design::DocumentDesign::MAX_COLUMNS) ],
      "body_line_count" => [ "3", I18n.t("design.page_section.errors.not_above_heading", lines: 6) ] }.each do |field, (value, message)|
      exports = count_exports { stub_preview { patch field_path, params: { field: field, value: value }, headers: STREAM } }
      assert_response :unprocessable_entity, field
      tpl = stream_template("page-section-content")
      assert_equal message, tpl.at_css("[data-field-error='#{field}']").text
      assert_equal value, tpl.at_css("input[name='page[#{field}]']")["value"]
      assert_equal 0, exports, field
    end
    @chapter.reload
    assert_equal 1, @chapter.column_count
    assert_nil @chapter[:body_line_count]
  end

  test "422 for the linked pair is all-or-nothing" do
    stub_preview { patch field_path, params: { values: { left_margin_mm: "70", right_margin_mm: "70" } }, headers: STREAM }
    assert_response :unprocessable_entity
    tpl = stream_template("page-section-content")
    %w[left_margin_mm right_margin_mm].each do |f|
      assert_equal I18n.t("design.page_section.errors.too_narrow", min: 20), tpl.at_css("[data-field-error='#{f}']").text
    end
    assert_equal [ 22, 22 ], [ @ps.reload.left_margin_mm.to_i, @ps.right_margin_mm.to_i ]
  end

  test "a pair with one valid side and one invalid writes neither" do
    exports = count_exports do
      stub_preview { patch field_path, params: { values: { left_margin_mm: "18", right_margin_mm: "abc" } }, headers: STREAM }
    end
    assert_response :unprocessable_entity
    tpl = stream_template("page-section-content")
    assert_equal I18n.t("design.page_section.errors.not_a_number"), tpl.at_css("[data-field-error='right_margin_mm']").text
    @ps.reload
    assert_equal [ 22, 22 ], [ @ps.left_margin_mm.to_i, @ps.right_margin_mm.to_i ]
    refute @ps.overridden?(:left_margin_mm) || @ps.overridden?(:right_margin_mm)
    assert_equal 0, exports
  end

  test "a 422's preview renders the stored margins, not the attempted ones" do
    seen = []
    stub_preview_capturing(->(kw) { seen << kw[:paper_size]&.top_margin_mm }) do
      patch field_path, params: { field: "top_margin_mm", value: "abc" }, headers: STREAM
    end
    assert_response :unprocessable_entity
    assert_equal [ 18 ], seen.uniq.map(&:to_i), "the preview was built from the stored top margin"
    refute_empty seen
  end

  test "422 names another doc type whose columns a margin would break" do
    @poem.update_columns(column_count: 3, gutter: 145) # poem (no binding): 108 mm = 306.1 pt fits; left 30 → 283.5 pt
    exports = count_exports { stub_preview { patch field_path, params: { field: "left_margin_mm", value: "30" }, headers: STREAM } }
    assert_response :unprocessable_entity
    assert_includes stream_template("page-section-content").at_css("[data-field-error='left_margin_mm']").text,
                    I18n.t("design.doc_types.poem")
    @ps.reload
    assert_equal 22, @ps.left_margin_mm.to_i
    refute @ps.overridden?(:left_margin_mm)
    assert_equal 0, exports
  end

  test "emptying column_count or gutter (PATCH \"\") is a 422 필수; nothing written" do
    %w[column_count gutter].each do |field|
      exports = count_exports { stub_preview { patch field_path, params: { field: field, value: "" }, headers: STREAM } }
      assert_response :unprocessable_entity, field
      assert_equal I18n.t("design.page_section.errors.required"),
                   stream_template("page-section-content").at_css("[data-field-error='#{field}']").text
      assert_equal 0, exports, field
    end
    @chapter.reload
    assert_equal 1, @chapter.column_count
    assert_equal 10, @chapter.gutter.to_i
  end

  test "margin revert: back to the generated value, unmarked, updated_at bumped" do
    @ps.update!(top_margin_mm: 30, overridden_fields: %w[top_margin_mm])
    @ps.update_columns(updated_at: 1.hour.ago)
    stub_preview { delete field_path, params: { field: "top_margin_mm" }, headers: STREAM }
    assert_response :success
    @ps.reload
    assert_equal Design::GenerationRules.margins_for(152, 225)[:top], @ps.top_margin_mm.to_f
    refute @ps.overridden?(:top_margin_mm)
    assert_operator @ps.updated_at, :>, 1.minute.ago
  end

  test "a margin revert that would newly break a doc type's columns is a 422 naming it; nothing written" do
    @ps.update!(left_margin_mm: 15, overridden_fields: %w[left_margin_mm])
    @poem.update_columns(column_count: 3, gutter: 155) # 310 pt: fits at left 15 (115 mm = 326 pt), not at the rule's 22 (306.1 pt)
    exports = count_exports { stub_preview { delete field_path, params: { field: "left_margin_mm" }, headers: STREAM } }
    assert_response :unprocessable_entity
    assert_includes stream_template("page-section-content").at_css("[data-field-error='left_margin_mm']").text,
                    I18n.t("design.doc_types.poem")
    @ps.reload
    assert_equal 15, @ps.left_margin_mm.to_i
    assert @ps.overridden?(:left_margin_mm)
    assert_equal 0, exports
  end

  test "body_line_count revert skips validations: a legacy row that fails another one still reverts" do
    @chapter.update_columns(body_line_count: 20, has_document_cover: true, cover_type: "bogus", updated_at: 1.hour.ago)
    refute @chapter.reload.valid?, "the legacy row fails cover_type"
    count_exports { stub_preview { delete field_path, params: { field: "body_line_count" }, headers: STREAM } } # export! stubbed
    assert_response :success
    @chapter.reload
    assert_nil @chapter[:body_line_count]
    assert_operator @chapter.updated_at, :>, 1.minute.ago, "the preview fingerprint still changes"
  end

  test "a blank PATCH of a margin reverts it too; body_line_count revert → nil (the paper size's)" do
    @ps.update!(top_margin_mm: 30, overridden_fields: %w[top_margin_mm])
    count_exports { stub_preview { patch field_path, params: { field: "top_margin_mm", value: " " }, headers: STREAM } }
    assert_response :success
    assert_equal 18, @ps.reload.top_margin_mm.to_i
    refute @ps.overridden?(:top_margin_mm), "the overridden mark is removed"
    @chapter.update!(body_line_count: 20)
    stub_preview { delete field_path, params: { field: "body_line_count" }, headers: STREAM }
    assert_response :success
    assert_nil @chapter.reload[:body_line_count]
    assert_nil stream_template("page-section-content").at_css("input[name='page[body_line_count]']")["value"]
  end

  test "a blank PATCH of body_line_count reverts it to nil (the paper size's)" do
    @chapter.update!(body_line_count: 20)
    exports = count_exports { stub_preview { patch field_path, params: { field: "body_line_count", value: "" }, headers: STREAM } }
    assert_response :success
    assert_nil @chapter.reload[:body_line_count]
    assert_equal 1, exports
  end

  test "render_preview=0 skips the preview stream" do
    exports = count_exports { patch field_path, params: { field: "gutter", value: "12", render_preview: "0" }, headers: STREAM }
    assert_response :success
    refute stream_attrs.any? { |a| a["target"] == "preview_frame" }
    assert_equal 1, exports
  end

  test "render_preview=0 skips the preview stream on a 422 and on DELETE" do
    count_exports { patch field_path, params: { field: "top_margin_mm", value: "abc", render_preview: "0" }, headers: STREAM }
    assert_response :unprocessable_entity
    assert stream_attrs.any? { |a| a["target"] == "page-section-content" }
    refute stream_attrs.any? { |a| a["target"] == "preview_frame" }
    @ps.update!(top_margin_mm: 30, overridden_fields: %w[top_margin_mm])
    count_exports { delete field_path, params: { field: "top_margin_mm", render_preview: "0" }, headers: STREAM }
    assert_response :success
    refute stream_attrs.any? { |a| a["target"] == "preview_frame" }
  end

  test "the preview stream honours the print cookie" do
    cookies["design_preview_print"] = "1"
    modes = []
    original = Design::PreviewService.method(:new)
    Design::PreviewService.define_singleton_method(:new) do |_dd, **kw|
      modes << kw[:print_mode]
      Object.new.tap { |f| f.define_singleton_method(:generate) { { success: true, print_mode: true, page_width: 432.0, page_height: 648.0, error: nil, pages: [ { jpg_path: "/tmp/p.jpg", overlay_data: [] } ] } } }
    end
    count_exports { patch field_path, params: { field: "gutter", value: "12" }, headers: STREAM }
    assert_equal [ true ], modes
    assert_includes stream_template("preview_frame").at_css("img")["src"], "print=1"
  ensure
    Design::PreviewService.singleton_class.send(:define_method, :new, original) if original
  end

  test "a read-only (system) theme is 403" do
    theme = Design::Theme.create!(name: "Sys #{SecureRandom.hex(3)}", locale: "ko", user_id: nil)
    ps = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.create!(doc_type: "chapter")
    path = design.field_theme_paper_size_document_design_page_path(theme, ps, dd)
    patch path, params: { field: "top_margin_mm", value: "20" }
    assert_response :forbidden
    delete path, params: { field: "top_margin_mm" }
    assert_response :forbidden
    assert_equal 18, ps.reload.top_margin_mm.to_i
  end
end
