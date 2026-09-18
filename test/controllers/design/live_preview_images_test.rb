require "test_helper"

# Live preview (POST preview) renders an UNSAVED copy of the design. Its images
# must show that copy and must not disturb the saved design's cached preview.
# Real renders (no service stub): the bug lived in the cache/serving path.
class Design::LivePreviewImagesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @theme = Design::Theme.create!(name: "LPI #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "chapter")
  end

  teardown do
    Design::PreviewService.new(@dd, paper_size: @ps).clear_cache
  end

  def preview_path = design.preview_theme_paper_size_document_design_path(@theme, @ps, @dd)

  def live_preview!(heading_lines)
    post preview_path, params: { document_design: { heading_height_in_lines: heading_lines } },
                       headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    Nokogiri::HTML(response.body).css("img").map { |img| img["src"] }
  end

  def image_bytes(src)
    get src
    assert_response :success
    response.body.b
  end

  def saved_page1_bytes
    File.binread(Design::PreviewService.new(@dd.reload, paper_size: @ps).generate[:jpg_path])
  end

  test "live preview images show the unsaved edit, not the saved design" do
    live = image_bytes(live_preview!(12).first)
    refute_equal saved_page1_bytes, live, "page 1 of the live preview is the saved design's render"
    assert_equal 6, @dd.reload.heading_height_in_lines, "nothing persisted"
  end

  test "two different unsaved edits give two different images" do
    first = image_bytes(live_preview!(10).first)
    second = image_bytes(live_preview!(14).first)
    refute_equal first, second
  end

  test "a live preview leaves the saved design's cached preview alone" do
    service = Design::PreviewService.new(@dd, paper_size: @ps)
    service.generate
    stamp = File.join(File.dirname(service.jpg_path), "cache_stamp.json")
    before = [ File.read(stamp), File.binread(service.jpg_path) ]

    src = live_preview!(12).first
    # Checked before the image loads too: loading it used to re-render the saved
    # design over the live one, which put the cache back by accident.
    assert_equal before, [ File.read(stamp), File.binread(service.jpg_path) ], "after the live render"
    image_bytes(src)
    assert_equal before, [ File.read(stamp), File.binread(service.jpg_path) ], "after its image loaded"
  end

  test "live image URLs are served as rendered, without re-rendering" do
    src = live_preview!(12).first
    assert_match(/[?&]live=[0-9a-f]+/, src)
    renders = 0
    original = Design::PreviewService.method(:new)
    Design::PreviewService.singleton_class.send(:define_method, :new) { |*a, **k| renders += 1; original.call(*a, **k) }
    begin
      image_bytes(src)
    ensure
      Design::PreviewService.singleton_class.send(:define_method, :new, original)
    end
    assert_equal 0, renders
  end

  test "an unknown or malformed live token is a 404" do
    jpg = ->(live) { design.preview_jpg_theme_paper_size_document_design_path(@theme, @ps, @dd, page: 1, live: live) }
    get jpg.("0123456789abcdef")
    assert_response :not_found
    get jpg.("../../etc")
    assert_response :not_found
  end
end
