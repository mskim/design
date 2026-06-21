require "test_helper"

class Design::DocumentDesignsOverrideTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @theme = Design::Theme.create!(name: "Override #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "chapter")
    @base_style = @theme.base_paragraph_styles.create!(name: "body", font_size: 10, font: "NotoSerifKR")
  end

  # ── override (collection POST) ──

  test "override creates a document-level paragraph_style copying base attrs" do
    assert_difference -> { @dd.paragraph_styles.count }, 1 do
      post design.override_theme_paper_size_document_design_paragraph_styles_path(@theme, @ps, @dd),
           params: { name: "body" }
    end
    assert_response :success
    style = @dd.paragraph_styles.find_by!(name: "body")
    assert_equal 10.0, style.font_size
    assert_equal "NotoSerifKR", style.font
  end

  test "override response targets properties_panel turbo-frame" do
    post design.override_theme_paper_size_document_design_paragraph_styles_path(@theme, @ps, @dd),
         params: { name: "body" }
    assert_response :success
    assert_select "turbo-frame#properties_panel"
  end

  test "override is idempotent – second call does not duplicate" do
    post design.override_theme_paper_size_document_design_paragraph_styles_path(@theme, @ps, @dd),
         params: { name: "body" }
    assert_difference -> { @dd.paragraph_styles.count }, 0 do
      post design.override_theme_paper_size_document_design_paragraph_styles_path(@theme, @ps, @dd),
           params: { name: "body" }
    end
    assert_response :success
  end

  test "override returns 403 for system theme" do
    system_theme = Design::Theme.create!(name: "Sys #{SecureRandom.hex(3)}", locale: "ko", user_id: nil)
    sys_ps = system_theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    sys_dd = sys_ps.document_designs.create!(doc_type: "chapter")
    post design.override_theme_paper_size_document_design_paragraph_styles_path(system_theme, sys_ps, sys_dd),
         params: { name: "body" }
    assert_response :forbidden
  end

  # ── revert (member DELETE) ──

  test "revert destroys the override paragraph_style" do
    override = @dd.paragraph_styles.create!(name: "body", font_size: 10)
    assert_difference -> { @dd.paragraph_styles.count }, -1 do
      delete design.revert_theme_paper_size_document_design_paragraph_style_path(@theme, @ps, @dd, override)
    end
    assert_response :success
  end

  test "revert re-renders properties_panel turbo-frame (not a redirect)" do
    override = @dd.paragraph_styles.create!(name: "body", font_size: 10)
    delete design.revert_theme_paper_size_document_design_paragraph_style_path(@theme, @ps, @dd, override)
    assert_response :success
    assert_select "turbo-frame#properties_panel"
  end

  test "revert returns 403 for system theme" do
    system_theme = Design::Theme.create!(name: "Sys2 #{SecureRandom.hex(3)}", locale: "ko", user_id: nil)
    sys_ps = system_theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    sys_dd = sys_ps.document_designs.create!(doc_type: "chapter")
    style = sys_dd.paragraph_styles.create!(name: "body", font_size: 10)
    delete design.revert_theme_paper_size_document_design_paragraph_style_path(system_theme, sys_ps, sys_dd, style)
    assert_response :forbidden
  end

  # ── new/create ──

  test "new renders the Panel form for a new paragraph_style" do
    get design.new_theme_paper_size_document_design_paragraph_style_path(@theme, @ps, @dd)
    assert_response :success
    assert_select "turbo-frame#properties_panel"
  end

  test "create persists a new paragraph_style" do
    assert_difference -> { @dd.paragraph_styles.count }, 1 do
      post design.theme_paper_size_document_design_paragraph_styles_path(@theme, @ps, @dd),
           params: { paragraph_style: { name: "footnote", font_size: 8 } }
    end
    assert_response :success
  end

  test "create with invalid params returns 422 and re-renders" do
    post design.theme_paper_size_document_design_paragraph_styles_path(@theme, @ps, @dd),
         params: { paragraph_style: { name: "", font_size: 8 } }
    assert_response :unprocessable_entity
    assert_select "turbo-frame#properties_panel"
  end

  test "create returns 403 for system theme" do
    system_theme = Design::Theme.create!(name: "Sys3 #{SecureRandom.hex(3)}", locale: "ko", user_id: nil)
    sys_ps = system_theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    sys_dd = sys_ps.document_designs.create!(doc_type: "chapter")
    post design.theme_paper_size_document_design_paragraph_styles_path(system_theme, sys_ps, sys_dd),
         params: { paragraph_style: { name: "body", font_size: 10 } }
    assert_response :forbidden
  end

  test "new returns 403 for system theme" do
    system_theme = Design::Theme.create!(name: "Sys4 #{SecureRandom.hex(3)}", locale: "ko", user_id: nil)
    sys_ps = system_theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    sys_dd = sys_ps.document_designs.create!(doc_type: "chapter")
    get design.new_theme_paper_size_document_design_paragraph_style_path(system_theme, sys_ps, sys_dd)
    assert_response :forbidden
  end

  # ── Panel layout: Revert link presence ──

  test "override panel response includes Revert link (it is a document override + editable)" do
    post design.override_theme_paper_size_document_design_paragraph_styles_path(@theme, @ps, @dd),
         params: { name: "body" }
    assert_response :success
    # Revert link must be present for a freshly-created document override
    assert_includes response.body, "Revert"
    assert_includes response.body, "data-turbo-method=\"delete\""
  end

  test "panel for a base/theme-level style shows NO Revert link" do
    get design.panel_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "theme", style_id: @base_style.id)
    assert_response :success
    refute_includes response.body, "Revert"
  end

  test "panel for a document override shows Revert link" do
    override = @dd.paragraph_styles.create!(name: "body", font_size: 10)
    get design.panel_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "document", style_id: override.id)
    assert_response :success
    assert_includes response.body, "Revert"
    assert_includes response.body, "data-turbo-method=\"delete\""
  end

  test "new (unsaved style) panel shows NO Revert link" do
    get design.new_theme_paper_size_document_design_paragraph_style_path(@theme, @ps, @dd)
    assert_response :success
    refute_includes response.body, "Revert"
  end

  test "panel for a document override shows Back link targeting properties_panel" do
    override = @dd.paragraph_styles.create!(name: "body", font_size: 10)
    get design.panel_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "document", style_id: override.id)
    assert_response :success
    assert_includes response.body, "data-turbo-frame=\"properties_panel\""
    assert_includes response.body, "Back"
  end

  test "override re-exports the render .db so the new override renders" do
    # custom themes export under user_<id>/ (see ThemeDbExportService#export_dir)
    db_path = File.join(Design.themes_dir, "user_#{@theme.user_id}", "#{@theme.name.parameterize}.db")
    File.delete(db_path) if File.exist?(db_path)
    post design.override_theme_paper_size_document_design_paragraph_styles_path(@theme, @ps, @dd),
         params: { name: "body" }
    assert File.exist?(db_path), "override must export the theme's render .db (preview stays in sync)"
  ensure
    File.delete(db_path) if db_path && File.exist?(db_path)
  end
end
