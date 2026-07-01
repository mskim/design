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

  # The standalone document/base style lists below the tabs were removed; styles are
  # edited via the 단락정의 (typography) tab and by clicking styles in the preview.
  test "edit page no longer renders the standalone style lists" do
    @dd.paragraph_styles.create!(name: "caption")
    get design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
    assert_response :success
    assert_select "h2", text: I18n.t("design.editor.document_styles"), count: 0
    assert_select "h2", text: I18n.t("design.editor.base_text_styles"), count: 0
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

  test "update persists image_opacity + logo params for a front_page design" do
    front_page = @ps.document_designs.create!(doc_type: "front_page")
    patch design.theme_paper_size_document_design_path(@theme, @ps, front_page), params: { document_design: {
      image_opacity: 40, logo_width: 25, logo_height: 10, logo_position: "left", logo_offset: 3
    } }
    assert_response :redirect
    front_page.reload
    assert_equal 40, front_page.image_opacity
    assert_equal "left", front_page.logo_position
    assert_in_delta 25.0, front_page.logo_width.to_f, 0.001
    assert_in_delta 10.0, front_page.logo_height.to_f, 0.001
    assert_in_delta 3.0, front_page.logo_offset.to_f, 0.001
  end

  test "edit shows image_opacity for a cover panel and logo only for front_page" do
    front_page = @ps.document_designs.create!(doc_type: "front_page")
    get design.edit_theme_paper_size_document_design_path(@theme, @ps, front_page)
    assert_response :success
    assert_select "[name='document_design[image_opacity]']"
    assert_select "[name='document_design[logo_position]']"

    # interior doc_type (@dd is a chapter): neither section renders
    get design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
    assert_response :success
    assert_select "[name='document_design[image_opacity]']", count: 0
    assert_select "[name='document_design[logo_position]']", count: 0
  end

  test "edit renders the editor toolbar with clickable theme and paper-size links" do
    get design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
    assert_response :success
    assert_select "a[href=?]", design.theme_path(@theme)
    assert_select "a[href=?]", design.edit_theme_paper_size_path(@theme, @ps)
  end

  test "edit renders the doc-type dropdown wired to design--dropdown" do
    get design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
    assert_select "[data-controller~='design--dropdown']"
    assert_select "[data-design--dropdown-target='menu']"
  end

  test "doc-type switcher lists interior siblings in reading order, excludes cover panels, marks current" do
    title    = @ps.document_designs.create!(doc_type: "title_page")
    epilogue = @ps.document_designs.create!(doc_type: "epilogue")
    cover    = @ps.document_designs.create!(doc_type: "front_page") # must be excluded
    get design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd) # @dd = chapter
    body = response.body

    title_path    = design.edit_theme_paper_size_document_design_path(@theme, @ps, title)
    chapter_path  = design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
    epilogue_path = design.edit_theme_paper_size_document_design_path(@theme, @ps, epilogue)
    cover_path    = design.edit_theme_paper_size_document_design_path(@theme, @ps, cover)

    # reading order: title_page (front) < chapter (body) < epilogue (rear)
    assert body.index(title_path) < body.index(chapter_path), "title_page before chapter"
    assert body.index(chapter_path) < body.index(epilogue_path), "chapter before epilogue"
    # cover panel excluded from the switcher
    assert_select "a[href=?]", cover_path, count: 0
    # current doc design highlighted
    assert_select "a.bg-blue-50[href=?]", chapter_path
  end
end
