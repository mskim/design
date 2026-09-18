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

  { "theme" => ->(t, ps, dd) { t.base_paragraph_styles.find_or_create_by!(name: "body") },
    "paper" => ->(t, ps, dd) { ps.paragraph_styles.create!(name: "body") },
    "document" => ->(t, ps, dd) { dd.paragraph_styles.create!(name: "body") } }.each do |level, make|
    test "old panel?level=#{level} links redirect to the name-keyed style (frame requests too)" do
      style = make.(@theme, @ps, @dd)
      target = design.theme_paper_size_document_design_style_path(@theme, @ps, @dd, "body")
      get design.panel_theme_paper_size_document_design_path(@theme, @ps, @dd, level: level, style_id: style.id)
      assert_redirected_to target
      get design.panel_theme_paper_size_document_design_path(@theme, @ps, @dd, level: level, style_id: style.id),
          headers: { "Turbo-Frame" => "properties_panel" }
      assert_redirected_to target
    end
  end

  test "invalid level raises RecordNotFound (404)" do
    get design.panel_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "bogus", style_id: 1)
    assert_response :not_found
  end

  test "writer forbidden from panel" do
    sign_in :kevin
    get design.panel_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "theme", style_id: 1)
    assert_response :forbidden
  end

  # An old level/style_id link can outlive its row (a reverted doc-type style, a
  # stale bookmark or browser-back entry). Following it must degrade gracefully,
  # not 500.
  test "panel for a destroyed document override redirects to the editor (full navigation)" do
    override = @dd.paragraph_styles.create!(name: "title", font_size: 20)
    gone_id = override.id
    override.destroy

    get design.panel_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "document", style_id: gone_id)
    assert_redirected_to design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
  end

  test "panel for a destroyed document override re-renders the properties panel (turbo-frame)" do
    override = @dd.paragraph_styles.create!(name: "title", font_size: 20)
    gone_id = override.id
    override.destroy

    get design.panel_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "document", style_id: gone_id),
        headers: { "Turbo-Frame" => "properties_panel" }
    assert_response :success
    assert_select "turbo-frame#properties_panel"
  end
end
