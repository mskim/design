require "test_helper"

class Design::DocumentDesignsEditTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @theme = Design::Theme.create!(name: "Owned #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "chapter")
  end

  # ── Tabbed PropertiesPanel is now the right pane ──

  test "edit renders the tabbed PropertiesPanel (ruby-ui--tabs data-controller present)" do
    get design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
    assert_response :success
    assert_select "body.design-studio"
    assert_select "[data-controller~='ruby-ui--tabs']"
  end

  test "edit renders Layout, Typography, and Header/Footer tab triggers" do
    get design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
    assert_response :success
    assert_includes response.body, "Layout"
    assert_includes response.body, "Typography"
    assert_includes response.body, "Header/Footer"
  end

  test "edit renders a submit button for a custom (editable) theme" do
    get design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
    assert_response :success
    assert_select "button[type='submit']", text: "Save"
  end

  test "system theme edit returns forbidden (ensure_theme_editable guard)" do
    system_theme = Design::Theme.create!(name: "Seoul #{SecureRandom.hex(3)}", locale: "ko", user_id: nil)
    sys_ps = system_theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    sys_dd = sys_ps.document_designs.create!(doc_type: "chapter")
    get design.edit_theme_paper_size_document_design_path(system_theme, sys_ps, sys_dd)
    assert_response :forbidden
  end

  # ── properties_panel endpoint ──

  test "properties_panel endpoint renders the PropertiesPanel frame with tabs" do
    get design.properties_panel_theme_paper_size_document_design_path(@theme, @ps, @dd)
    assert_response :success
    assert_select "turbo-frame#properties_panel"
    assert_select "[data-controller~='ruby-ui--tabs']"
  end

  test "properties_panel endpoint renders submit button for editable custom theme" do
    get design.properties_panel_theme_paper_size_document_design_path(@theme, @ps, @dd)
    assert_response :success
    assert_select "button[type='submit']", text: "Save"
  end

  test "properties_panel endpoint returns forbidden for system theme" do
    system_theme = Design::Theme.create!(name: "Seoul #{SecureRandom.hex(3)}", locale: "ko", user_id: nil)
    sys_ps = system_theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    sys_dd = sys_ps.document_designs.create!(doc_type: "chapter")
    get design.properties_panel_theme_paper_size_document_design_path(system_theme, sys_ps, sys_dd)
    assert_response :forbidden
  end

  # ── update ──

  test "update persists and redirects" do
    patch design.theme_paper_size_document_design_path(@theme, @ps, @dd), params: { document_design: { column_count: 2 } }
    assert_response :redirect
    assert_equal 2, @dd.reload.column_count
  end

  test "update persists the newly-ported text_box / page_bg / document_cover fields" do
    patch design.theme_paper_size_document_design_path(@theme, @ps, @dd), params: {
      document_design: {
        text_box_anchor_position: 5, text_box_grid_width: 4, text_box_grid_height: 6,
        page_bg_color: "CMYK=0,0,0,20", has_document_cover: "1", cover_type: "spread"
      }
    }
    assert_response :redirect
    @dd.reload
    assert_equal 5, @dd.text_box_anchor_position
    assert_equal 4, @dd.text_box_grid_width
    assert_equal 6, @dd.text_box_grid_height
    assert_equal "CMYK=0,0,0,20", @dd.page_bg_color
    assert @dd.has_document_cover?
    assert_equal "spread", @dd.cover_type
  end
end
