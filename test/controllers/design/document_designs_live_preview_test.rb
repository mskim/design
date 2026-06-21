require "test_helper"

class Design::DocumentDesignsLivePreviewTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @theme = Design::Theme.create!(name: "LP #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "chapter", column_count: 1)
  end

  test "POST preview replaces preview_frame and does NOT persist" do
    fake = Object.new
    def fake.generate = { success: true, jpg_path: "/tmp/x.jpg", overlay_data: [], page_width: 432.0, page_height: 648.0, error: nil }
    captured = nil
    original = Design::PreviewService.method(:new)
    Design::PreviewService.define_singleton_method(:new) { |dd, **| captured = dd; fake }
    begin
      post design.preview_theme_paper_size_document_design_path(@theme, @ps, @dd),
           params: { document_design: { column_count: 3 } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    ensure
      Design::PreviewService.define_singleton_method(:new, original)
    end
    assert_response :success
    assert_includes response.media_type, "turbo-stream"
    assert_includes response.body, "preview_frame"
    assert_equal 3, captured.column_count        # preview used the UNSAVED value
    assert_equal 1, @dd.reload.column_count       # NOT persisted
  end

  test "writer forbidden from POST preview" do
    sign_in :kevin
    post design.preview_theme_paper_size_document_design_path(@theme, @ps, @dd)
    assert_response :forbidden
  end

  test "GET preview (C3a lazy) still renders" do
    fake = Object.new
    def fake.generate = { success: true, jpg_path: "/tmp/x.jpg", overlay_data: [], page_width: 432.0, page_height: 648.0, error: nil }
    original = Design::PreviewService.method(:new)
    Design::PreviewService.define_singleton_method(:new) { |dd, **| fake }
    begin
      get design.preview_theme_paper_size_document_design_path(@theme, @ps, @dd)
    ensure
      Design::PreviewService.define_singleton_method(:new, original)
    end
    assert_response :success
    assert_includes response.body, "preview_frame"
  end
end
