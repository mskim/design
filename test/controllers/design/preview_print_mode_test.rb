require "test_helper"

# The studio always previews in print mode: every preview endpoint builds
# PreviewService with print_mode: true (the service drops it where the binding
# doesn't apply), and the frame's JPG URLs carry print=1 when the result says it
# applied. preview_jpg renders print mode only for print=1 (the theme page's
# cards call it without, and stay normal).
class Design::PreviewPrintModeTest < ActionDispatch::IntegrationTest
  STREAM = { "Accept" => "text/vnd.turbo-stream.html" }.freeze
  JPG = Rails.root.join("test/fixtures/files/white-rabbit.webp").to_s

  setup do
    sign_in :david
    @theme = Design::Theme.create!(name: "PPM #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "chapter")
  end

  # Records each PreviewService.new's print_mode; the fake result echoes it.
  def capture_print_modes
    modes = []
    original = Design::PreviewService.method(:new)
    Design::PreviewService.define_singleton_method(:new) do |_dd, **kw|
      modes << kw[:print_mode]
      result = { success: true, print_mode: kw[:print_mode] == true, page_width: 432.0, page_height: 648.0, error: nil,
                 pages: [ { jpg_path: JPG, overlay_data: [] }, { jpg_path: JPG, overlay_data: [] } ] }
      Object.new.tap { |fake| fake.define_singleton_method(:generate) { result } }
    end
    yield
    modes
  ensure
    Design::PreviewService.singleton_class.send(:define_method, :new, original)
  end

  def preview_path = design.preview_theme_paper_size_document_design_path(@theme, @ps, @dd)
  def jpg_path(**q) = design.preview_jpg_theme_paper_size_document_design_path(@theme, @ps, @dd, **q)

  test "GET preview with no cookie renders print mode with print=1 image URLs" do
    assert_equal [ true ], capture_print_modes { get preview_path }
    assert_select "turbo-frame#preview_frame img[src*='print=1']", 2
  end

  test "a leftover design_preview_print cookie changes nothing" do
    [ "", "0", "1" ].each do |value|
      cookies["design_preview_print"] = value
      assert_equal [ true ], capture_print_modes { get preview_path }, value
    end
  end

  # Not stubbed: the service decides print mode doesn't apply to a blank page,
  # which still previews normally.
  test "a blank page (no binding) previews normally, with no print=1 image URLs" do
    dd = @ps.document_designs.create!(doc_type: "blank_page")
    refute dd.binding_applies?
    get design.preview_theme_paper_size_document_design_path(@theme, @ps, dd)
    assert_response :success
    assert_select "turbo-frame#preview_frame img", minimum: 1
    assert_select "img[src*='print=1']", 0
  ensure
    Design::PreviewService.new(dd, paper_size: @ps).clear_cache if dd
  end

  # Not stubbed: the frame's first page box carries the binding (pt) because
  # the service rendered the chapter in print mode.
  test "a chapter's guide geometry carries the binding with no cookie" do
    assert_operator @ps.binding_margin_pt, :>, 0
    get preview_path
    assert_response :success
    geometry = JSON.parse(css_select("[data-design--page-guides-geometry-value]").first["data-design--page-guides-geometry-value"])
    assert_in_delta @ps.binding_margin_pt, geometry["binding"], 0.01
  ensure
    Design::PreviewService.new(@dd, paper_size: @ps, print_mode: true).clear_cache
  end

  test "POST preview (live preview) renders print mode" do
    modes = capture_print_modes do
      post preview_path, params: { document_design: { heading_height_in_lines: 4 } }, headers: STREAM
    end
    assert_equal [ true ], modes
    assert_includes response.body, "print=1"
  end

  test "preview_jpg renders print mode only for print=1" do
    assert_equal [ false ], capture_print_modes { get jpg_path }
    assert_response :success
    assert_equal [ true ], capture_print_modes { get jpg_path(print: 1, page: 2) }
    assert_response :success
    assert_equal [ false ], capture_print_modes { get jpg_path(print: "true") }
  end

  test "a style save's preview stream renders print mode" do
    @theme.base_paragraph_styles.create!(name: "zz_body", font_size: 10)
    modes = capture_print_modes do
      patch design.field_theme_paper_size_document_design_style_path(@theme, @ps, @dd, "zz_body"),
            params: { field: "font_size", value: "12" }, headers: STREAM
    end
    assert_response :success
    assert_equal [ true ], modes
    assert_includes response.body, "print=1"
  end
end
