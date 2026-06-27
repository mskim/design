require "test_helper"

class Design::DocumentDesignsPanelTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @theme = Design::Theme.create!(name: "PP #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "chapter")
  end

  test "edit right pane is a properties_panel frame holding the tabbed PropertiesPanel form" do
    get design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
    assert_response :success
    assert_select "turbo-frame#properties_panel form[data-controller~='design--live-preview']"
    assert_select "[data-controller~='ruby-ui--tabs']"
  end

  test "properties_panel endpoint renders the tabbed PropertiesPanel frame" do
    get design.properties_panel_theme_paper_size_document_design_path(@theme, @ps, @dd)
    assert_response :success
    assert_select "turbo-frame#properties_panel form[data-controller~='design--live-preview']"
    assert_select "[data-controller~='ruby-ui--tabs']"
  end

  test "panel renders the autosave Panel for a theme-level style" do
    theme_style = @theme.base_paragraph_styles.create!(name: "body")
    get design.panel_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "theme", style_id: theme_style.id)
    assert_response :success
    assert_select "turbo-frame#properties_panel form[data-controller~='design--panel-autosave']"
    assert_includes response.body, %(name="paragraph_style[font_size]")
  end

  test "panel full navigation (preview click) renders a full page with preview on the left" do
    theme_style = @theme.base_paragraph_styles.create!(name: "body")
    get design.panel_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "theme", style_id: theme_style.id)
    assert_response :success
    # Full page: the document preview AND the style's edit form.
    assert_select "turbo-frame#preview_frame"
    assert_select "turbo-frame#properties_panel form[data-controller~='design--panel-autosave']"
  end

  test "panel as a turbo-frame request renders only the bare panel (embedded, no preview)" do
    theme_style = @theme.base_paragraph_styles.create!(name: "body")
    get design.panel_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "theme", style_id: theme_style.id),
        headers: { "Turbo-Frame" => "properties_panel" }
    assert_response :success
    assert_select "turbo-frame#properties_panel"
    assert_select "turbo-frame#preview_frame", count: 0
  end

  test "panel_update saves the style at its level + replaces preview_frame" do
    theme_style = @theme.base_paragraph_styles.create!(name: "body", font_size: 10)
    fake = Object.new
    def fake.generate = { success: true, jpg_path: "/tmp/x.jpg", overlay_data: [], page_width: 432.0, page_height: 648.0, error: nil }
    original = Design::PreviewService.method(:new)
    Design::PreviewService.define_singleton_method(:new) { |*, **| fake }
    begin
      patch design.panel_update_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "theme", style_id: theme_style.id),
            params: { paragraph_style: { font_size: 18 } }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    ensure
      Design::PreviewService.define_singleton_method(:new, original)
    end
    assert_response :success
    assert_includes response.media_type, "turbo-stream"
    assert_includes response.body, "preview_frame"
    assert_equal 18.0, theme_style.reload.font_size
  end

  # ── Edit-in-place across ALL 3 levels (verification additions) ──

  def stub_preview
    fake = Object.new
    def fake.generate = { success: true, jpg_path: "/tmp/x.jpg", overlay_data: [], page_width: 432.0, page_height: 648.0, error: nil }
    original = Design::PreviewService.method(:new)
    Design::PreviewService.define_singleton_method(:new) { |*, **| fake }
    yield
  ensure
    Design::PreviewService.define_singleton_method(:new, original)
  end

  test "panel_update at level=paper updates the paper-size style record" do
    paper_style = @ps.paragraph_styles.create!(name: "caption", font_size: 9)
    stub_preview do
      patch design.panel_update_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "paper", style_id: paper_style.id),
            params: { paragraph_style: { font_size: 14 } }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    assert_includes response.body, "preview_frame"
    assert_equal 14.0, paper_style.reload.font_size
  end

  test "panel_update at level=document updates the document-design style record" do
    doc_style = @dd.paragraph_styles.create!(name: "quote", font_size: 11)
    stub_preview do
      patch design.panel_update_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "document", style_id: doc_style.id),
            params: { paragraph_style: { font_size: 22 } }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    assert_includes response.body, "preview_frame"
    assert_equal 22.0, doc_style.reload.font_size
  end

  test "panel_update does not cross levels: a document style id is not found at theme level (404)" do
    doc_style = @dd.paragraph_styles.create!(name: "quote2", font_size: 11)
    patch design.panel_update_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "theme", style_id: doc_style.id),
          params: { paragraph_style: { font_size: 22 } }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :not_found
    assert_equal 11.0, doc_style.reload.font_size
  end

  test "invalid level raises RecordNotFound (404)" do
    get design.panel_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "bogus", style_id: 1)
    assert_response :not_found
  end

  test "panel_update re-renders Panel at 422 on validation failure" do
    theme_style = @theme.base_paragraph_styles.create!(name: "valid", font_size: 10)
    patch design.panel_update_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "theme", style_id: theme_style.id),
          params: { paragraph_style: { name: "" } }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :unprocessable_entity
    assert_select "turbo-frame#properties_panel form[data-controller~='design--panel-autosave']"
  end

  test "writer forbidden from panel" do
    sign_in :kevin
    get design.panel_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "theme", style_id: 1)
    assert_response :forbidden
  end

  test "writer forbidden from panel_update" do
    sign_in :kevin
    patch design.panel_update_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "theme", style_id: 1),
          params: { paragraph_style: { font_size: 5 } }
    assert_response :forbidden
  end
end
