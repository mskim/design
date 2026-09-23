require "test_helper"

# D4 Object section endpoints: copyright's text box and the front wing's author
# photo, one field — or one whitelisted joint set — per request.
class Design::DocumentDesignObjectsTest < ActionDispatch::IntegrationTest
  STREAM = { "Accept" => "text/vnd.turbo-stream.html" }.freeze

  setup do
    sign_in :david
    @theme = Design::Theme.create!(name: "OB #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @copyright = @ps.document_designs.create!(doc_type: "copyright")
    @wing = @ps.document_designs.create!(doc_type: "front_wing")
    @chapter = @ps.document_designs.create!(doc_type: "chapter")
  end

  def field_path(dd = @copyright) = design.field_theme_paper_size_document_design_object_path(@theme, @ps, dd)

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

  test "PATCH a text-box field writes it and answers with a morph + preview" do
    exports = count_exports do
      stub_preview { patch field_path, params: { field: "text_box_grid_width", value: "3" }, headers: STREAM }
    end
    assert_response :success
    assert_equal 3, @copyright.reload.text_box_grid_width
    assert_equal 1, exports
    assert_includes stream_attrs, { "method" => "morph", "action" => "replace", "target" => "object-section-content" }
    assert stream_attrs.any? { |a| a["target"] == "preview_frame" }
    tpl = stream_template("object-section-content")
    assert tpl.at_css("div#object-section-content"), "the template root is the target"
    assert_equal "3", tpl.at_css("[name='object[text_box_grid_width]']")["value"]
    refute_includes response.body, "<html"
  end

  test "PATCH bumps updated_at so the preview's fingerprint changes" do
    @copyright.update_columns(updated_at: 1.day.ago)
    stub_preview { patch field_path, params: { field: "text_box_anchor_position", value: "5" }, headers: STREAM }
    assert_operator @copyright.reload.updated_at, :>, 1.minute.ago
  end

  test "the size pair is the one joint set, for a typed value and for a drag" do
    stub_preview do
      patch field_path, params: { values: { text_box_grid_width: "5", text_box_grid_height: "9" } }, headers: STREAM
    end
    assert_response :success
    assert_equal [ 5, 9 ], [ @copyright.reload.text_box_grid_width, @copyright.text_box_grid_height ]
  end

  test "the anchor is written on its own, leaving unset sizes unset" do
    stub_preview { patch field_path, params: { field: "text_box_anchor_position", value: "3" }, headers: STREAM }
    assert_response :success
    @copyright.reload
    assert_equal 3, @copyright.text_box_anchor_position
    assert_nil @copyright.text_box_grid_width, "the engine still defaults it to 4"
    assert_nil @copyright.text_box_grid_height
  end

  test "PATCH every photo field on the front wing" do
    { photo_grid_width: "5", photo_grid_height: "4", photo_anchor: "8", photo_fit: "contain",
      photo_border_width: "1.5", photo_border_color: "CMYK=0,0,0,60" }.each do |field, value|
      stub_preview { patch field_path(@wing), params: { field: field, value: value }, headers: STREAM }
      assert_response :success, field
    end
    @wing.reload
    assert_equal [ 5, 4, 8, "contain" ], [ @wing.photo_grid_width, @wing.photo_grid_height, @wing.photo_anchor,
                                           @wing.photo_fit ]
    assert_in_delta 1.5, @wing.photo_border_width.to_f, 0.001
    assert_equal "CMYK=0,0,0,60", @wing.photo_border_color
    stub_preview do
      patch field_path(@wing), params: { values: { photo_grid_width: "2", photo_grid_height: "2" } }, headers: STREAM
    end
    assert_response :success
    assert_equal [ 2, 2 ], [ @wing.reload.photo_grid_width, @wing.photo_grid_height ]
  end

  test "400: unknown field, non-String value, the other inspector's field, a doc type with no inspector" do
    [ { field: "bogus", value: "1" }, { field: "column_count", value: "1" },
      { field: "text_box_grid_width", value: [ "3" ] }, { field: "text_box_grid_width" },
      { field: "photo_anchor", value: "3" } ].each do |params|                    # photo on copyright
      exports = count_exports { patch field_path, params: params, headers: STREAM }
      assert_response :bad_request, params.inspect
      assert_equal 0, exports
    end
    patch field_path(@wing), params: { field: "text_box_grid_width", value: "3" }, headers: STREAM
    assert_response :bad_request, "the text box is not the wing's"
    patch field_path(@chapter), params: { field: "text_box_grid_width", value: "3" }, headers: STREAM
    assert_response :bad_request, "chapter has no inspector at all"
    assert_nil @copyright.reload.text_box_grid_width
  end

  test "400: a values set that isn't one this doc type writes together" do
    [ { text_box_grid_width: "2" },                                              # a subset
      { text_box_anchor_position: "3", text_box_grid_width: "2", text_box_grid_height: "5" }, # no longer a set
      { text_box_grid_width: "2", text_box_grid_height: "3", photo_anchor: "1" }, # never a set
      { photo_grid_width: "2", photo_grid_height: "2" },                          # the wing's set, on copyright
      { text_box_grid_width: [ "2" ], text_box_grid_height: "3" } ].each do |values|
      exports = count_exports { patch field_path, params: { values: values }, headers: STREAM }
      assert_response :bad_request, values.inspect
      assert_equal 0, exports
    end
    patch field_path, params: { values: "2" }, headers: STREAM
    assert_response :bad_request
  end

  test "400: DELETE of a field this doc type doesn't own" do
    %w[bogus photo_anchor column_count].each do |field|
      delete field_path, params: { field: field }, headers: STREAM
      assert_response :bad_request, field
    end
  end

  test "422: the attempted value and message are shown, nothing is written, the preview still refreshes" do
    exports = count_exports do
      stub_preview { patch field_path, params: { field: "text_box_grid_width", value: "9" }, headers: STREAM }
    end
    assert_response :unprocessable_entity
    tpl = stream_template("object-section-content")
    assert_equal I18n.t("design.object_section.errors.out_of_range", min: 1, max: 6),
                 tpl.at_css("[data-field-error='text_box_grid_width']").text
    assert_equal "9", tpl.at_css("[name='object[text_box_grid_width]']")["value"]
    assert_equal "6", tpl.at_css("[name='object[text_box_grid_height]']")["value"], "the others show stored values"
    assert stream_attrs.any? { |a| a["target"] == "preview_frame" }
    assert_nil @copyright.reload.text_box_grid_width
    assert_equal 0, exports
  end

  # "99" breaks the loose always-on rule too, which is why that rule stands
  # down inside :object_section — otherwise this field would carry two messages
  # and the section's, naming this page's grid, might not be the first.
  test "422 for a joint set is all-or-nothing, with one message under each bad field" do
    stub_preview do
      patch field_path, params: { values: { text_box_grid_width: "9", text_box_grid_height: "99" } }, headers: STREAM
    end
    assert_response :unprocessable_entity
    tpl = stream_template("object-section-content")
    assert_equal I18n.t("design.object_section.errors.out_of_range", min: 1, max: 6),
                 tpl.at_css("[data-field-error='text_box_grid_width']").text
    assert_equal I18n.t("design.object_section.errors.out_of_range", min: 1, max: 12),
                 tpl.at_css("[data-field-error='text_box_grid_height']").text
    assert_equal 2, tpl.css("[data-field-error]").size, "one message per field, not two"
    assert_equal [ "9", "99" ], [ tpl.at_css("[name='object[text_box_grid_width]']")["value"],
                                  tpl.at_css("[name='object[text_box_grid_height]']")["value"] ]
    @copyright.reload
    assert_nil @copyright.text_box_grid_width
    assert_nil @copyright.text_box_grid_height
  end

  test "422: a colour name (the renderers would draw no border)" do
    stub_preview { patch field_path(@wing), params: { field: "photo_border_color", value: "black" }, headers: STREAM }
    assert_response :unprocessable_entity
    assert_equal I18n.t("design.object_section.errors.bad_color"),
                 stream_template("object-section-content").at_css("[data-field-error='photo_border_color']").text
    assert_equal "#000000", @wing.reload.photo_border_color
  end

  test "revert: a text-box field goes back to nil (the engine's 7 / 4 / 6)" do
    @copyright.update!(text_box_anchor_position: 3, text_box_grid_width: 2)
    @copyright.update_columns(updated_at: 1.hour.ago)
    exports = count_exports do
      stub_preview { delete field_path, params: { field: "text_box_anchor_position" }, headers: STREAM }
    end
    assert_response :success
    @copyright.reload
    assert_nil @copyright.text_box_anchor_position
    assert_equal 2, @copyright.text_box_grid_width, "only the field asked for"
    assert_operator @copyright.updated_at, :>, 1.minute.ago
    assert_equal 1, exports
    assert_equal "7", stream_template("object-section-content").at_css("[name='object[text_box_anchor_position]']")["value"]
  end

  test "revert: a photo field goes back to its column default" do
    @wing.update!(photo_grid_width: 6, photo_fit: "contain", photo_border_color: "#ffffff")
    { "photo_grid_width" => 3, "photo_fit" => "cover", "photo_border_color" => "#000000" }.each do |field, default|
      stub_preview { delete field_path(@wing), params: { field: field }, headers: STREAM }
      assert_response :success, field
      assert_equal default, @wing.reload[field], field
    end
  end

  test "a blank PATCH reverts, and a legacy row failing an unrelated validation still reverts" do
    @copyright.update!(text_box_grid_width: 2)
    stub_preview { patch field_path, params: { field: "text_box_grid_width", value: " " }, headers: STREAM }
    assert_response :success
    assert_nil @copyright.reload.text_box_grid_width
    @wing.update_columns(photo_grid_width: 5, has_document_cover: true, cover_type: "bogus")
    refute @wing.reload.valid?, "the legacy row fails cover_type"
    stub_preview { delete field_path(@wing), params: { field: "photo_grid_width" }, headers: STREAM }
    assert_response :success
    assert_equal 3, @wing.reload.photo_grid_width
  end

  test "render_preview=0 skips the preview stream" do
    patch field_path, params: { field: "text_box_grid_width", value: "3", render_preview: "0" }, headers: STREAM
    assert_response :success
    refute stream_attrs.any? { |a| a["target"] == "preview_frame" }
  end

  # The restore is stub_preview's own form (document_design_styles_test.rb:34-37):
  # define_singleton_method with the captured Method object, so nothing is left
  # behind for the next test in this worker.
  test "the preview stream honours the print cookie" do
    cookies["design_preview_print"] = "1"
    modes = []
    original = Design::PreviewService.method(:new)
    Design::PreviewService.define_singleton_method(:new) do |_dd, **kw|
      modes << kw[:print_mode]
      Object.new.tap do |fake|
        fake.define_singleton_method(:generate) do
          { success: true, print_mode: true, page_width: 432.0, page_height: 648.0, error: nil,
            pages: [ { jpg_path: "/tmp/p.jpg", overlay_data: [] } ] }
        end
      end
    end
    patch field_path, params: { field: "text_box_grid_width", value: "3" }, headers: STREAM
    assert_equal [ true ], modes
    assert_includes stream_template("preview_frame").at_css("img")["src"], "print=1"
  ensure
    Design::PreviewService.define_singleton_method(:new, original) if original
  end

  test "403 for a read-only (system) theme, 404 for a design on another size" do
    theme = Design::Theme.create!(name: "Sys #{SecureRandom.hex(3)}", locale: "ko", user_id: nil)
    ps = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.create!(doc_type: "copyright")
    path = design.field_theme_paper_size_document_design_object_path(theme, ps, dd)
    patch path, params: { field: "text_box_grid_width", value: "2" }
    assert_response :forbidden
    delete path, params: { field: "text_box_grid_width" }
    assert_response :forbidden
    assert_nil dd.reload.text_box_grid_width

    other = @theme.paper_sizes.create!(size_name: "국판", width_mm: 148, height_mm: 210)
    patch design.field_theme_paper_size_document_design_object_path(@theme, other, @copyright),
          params: { field: "text_box_grid_width", value: "2" }
    assert_response :not_found
  end
end
