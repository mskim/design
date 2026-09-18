require "test_helper"

# 인쇄용 is view state in the design_preview_print cookie. The preview
# endpoints pass it to PreviewService, whose result says whether it applied;
# the frame's JPG URLs then carry print=1, and preview_jpg renders print mode
# only for print=1 (the theme page's cards call preview_jpg without it).
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
  def print_on! = cookies["design_preview_print"] = "1"

  test "GET preview: normal without the cookie; print mode with print=1 image URLs with it" do
    assert_equal [ false ], capture_print_modes { get preview_path }
    assert_select "img[src*='print=1']", 0
    print_on!
    assert_equal [ true ], capture_print_modes { get preview_path }
    assert_select "turbo-frame#preview_frame img[src*='print=1']", 2
  end

  test "only the cookie value \"1\" and print=1 turn print mode on" do
    [ "true", "0" ].each do |value|
      cookies["design_preview_print"] = value
      assert_equal [ false ], capture_print_modes { get preview_path }, value
      assert_select "img[src*='print=1']", 0
    end
    assert_equal [ false ], capture_print_modes { get jpg_path(print: "true") }
  end

  # Not stubbed: the service decides print mode doesn't apply to a blank page.
  test "a blank page with the cookie on renders no print=1 image URLs" do
    dd = @ps.document_designs.create!(doc_type: "blank_page")
    print_on!
    get design.preview_theme_paper_size_document_design_path(@theme, @ps, dd)
    assert_response :success
    assert_select "turbo-frame#preview_frame img", minimum: 1
    assert_select "img[src*='print=1']", 0
  ensure
    Design::PreviewService.new(dd, paper_size: @ps).clear_cache if dd
  end

  # Not stubbed: the frame's first page box carries the binding (pt) only when
  # the service rendered the chapter in print mode.
  test "a chapter's guide geometry carries the binding only with the cookie on" do
    assert_operator @ps.binding_margin_pt, :>, 0
    geometry = -> { JSON.parse(css_select("[data-design--page-guides-geometry-value]").first["data-design--page-guides-geometry-value"]) }
    get preview_path
    assert_response :success
    assert_equal 0.0, geometry.()["binding"]
    print_on!
    get preview_path
    assert_response :success
    assert_in_delta @ps.binding_margin_pt, geometry.()["binding"], 0.01
  ensure
    Design::PreviewService.new(@dd, paper_size: @ps).clear_cache
    Design::PreviewService.new(@dd, paper_size: @ps, print_mode: true).clear_cache
  end

  test "POST preview (live preview) honours the cookie" do
    print_on!
    modes = capture_print_modes do
      post preview_path, params: { document_design: { heading_height_in_lines: 4 } }, headers: STREAM
    end
    assert_equal [ true ], modes
    assert_includes response.body, "print=1"
  end

  test "preview_jpg renders print mode only for print=1, whatever the cookie" do
    print_on!
    assert_equal [ false ], capture_print_modes { get jpg_path }
    assert_response :success
    assert_equal [ true ], capture_print_modes { get jpg_path(print: 1, page: 2) }
    assert_response :success
  end

  test "a style save's preview stream honours the cookie" do
    @theme.base_paragraph_styles.create!(name: "zz_body", font_size: 10)
    print_on!
    modes = capture_print_modes do
      patch design.field_theme_paper_size_document_design_style_path(@theme, @ps, @dd, "zz_body"),
            params: { field: "font_size", value: "12" }, headers: STREAM
    end
    assert_response :success
    assert_equal [ true ], modes
    assert_includes response.body, "print=1"
  end
end
