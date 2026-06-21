require "test_helper"

class Design::DocumentDesignsPreviewTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @theme = Design::Theme.create!(name: "Owned #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "chapter")
  end

  test "edit embeds the lazy preview frame" do
    get design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
    assert_response :success
    assert_select "turbo-frame#preview_frame[src][loading=lazy]"
  end

  test "preview renders the Preview component (stubbed service)" do
    fake = Object.new
    def fake.generate = { success: true, jpg_path: "/tmp/x.jpg", overlay_data: [], page_width: 432.0, page_height: 648.0, error: nil }
    stub_preview_service(fake) do
      get design.preview_theme_paper_size_document_design_path(@theme, @ps, @dd)
    end
    assert_response :success
    assert_select "turbo-frame#preview_frame"
    assert_includes response.body, "<img"
  end

  test "preview renders PreviewError on failure (stubbed)" do
    fake = Object.new
    def fake.generate = { success: false, error: "boom" }
    stub_preview_service(fake) do
      get design.preview_theme_paper_size_document_design_path(@theme, @ps, @dd)
    end
    assert_response :success
    assert_includes response.body, "boom"
  end

  test "preview overlay zones are panel links targeting the properties_panel frame" do
    @theme.base_paragraph_styles.create!(name: "body") unless @theme.base_paragraph_styles.exists?(name: "body")
    fake = Object.new
    def fake.generate = { success: true, jpg_path: "/tmp/x.jpg", page_width: 432.0, page_height: 648.0, error: nil,
      overlay_data: [ { type: "paragraph", markup: "body", x: 1, y: 1, width: 5, height: 5 } ] }
    stub_preview_service(fake) do
      get design.preview_theme_paper_size_document_design_path(@theme, @ps, @dd)
    end
    assert_response :success
    assert_includes response.body, "/panel"          # panel URL, not edit
    assert_includes response.body, "level=theme"      # body is a theme-base style
    assert_includes response.body, %(data-turbo-frame="properties_panel")
  end

  test "writer is forbidden" do
    sign_in :kevin
    get design.preview_theme_paper_size_document_design_path(@theme, @ps, @dd)
    assert_response :forbidden
  end

  test "preview_jpg succeeds for a SYSTEM (read-only) theme" do
    system_theme = Design::Theme.create!(name: "Sys #{SecureRandom.hex(3)}", locale: "ko", user_id: nil)
    ps = system_theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.create!(doc_type: "chapter")

    fake = Object.new
    def fake.generate = { success: true, jpg_path: Rails.root.join("test/fixtures/files/white-rabbit.webp").to_s }
    stub_preview_service(fake) do
      get design.preview_jpg_theme_paper_size_document_design_path(system_theme, ps, dd)
    end

    assert_response :success
  end

  test "edit stays forbidden for a SYSTEM theme" do
    system_theme = Design::Theme.create!(name: "Sys #{SecureRandom.hex(3)}", locale: "ko", user_id: nil)
    ps = system_theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.create!(doc_type: "chapter")

    get design.edit_theme_paper_size_document_design_path(system_theme, ps, dd)
    assert_response :forbidden
  end

  private

  # Minitest 6 dropped Object#stub; swap the class .new manually and restore.
  def stub_preview_service(fake)
    original = Design::PreviewService.method(:new)
    Design::PreviewService.define_singleton_method(:new) { |*, **| fake }
    yield
  ensure
    Design::PreviewService.singleton_class.send(:define_method, :new, original)
  end
end
