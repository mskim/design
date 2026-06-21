require "test_helper"

# End-to-end integration test for the Typography paragraph-style editor flow.
# Exercises: merged-styles list → override → panel_update → revert (fallback)
# against a CUSTOM (editable) theme, signed in as david.
class Design::DocumentDesignsTypographyFlowTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @theme = Design::Theme.create!(
      name: "TypoFlow #{SecureRandom.hex(3)}",
      locale: "ko",
      user_id: users(:david).id
    )
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "chapter")
    # One base style – so merged_paragraph_styles has at least one entry
    @base_style = @theme.base_paragraph_styles.create!(name: "body", font_size: 10, font: "NotoSerifKR")
  end

  # ── Step 1: Typography tab lists merged styles ──

  test "GET edit – Typography tab is present and shows a base style with Edit affordance" do
    get design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
    assert_response :success

    # Typography tab trigger must be rendered
    assert_includes response.body, "Typography"

    # The base style name and the "(base)" badge must appear
    assert_includes response.body, "body"
    assert_includes response.body, "(base)"

    # Edit affordance is present (POST override link) for an editable theme
    assert_includes response.body, "Edit"
  end

  # ── Step 2: POST override creates a document-level override and renders the Panel ──

  test "POST override – creates doc-level override copy of base attrs and renders Panel in properties_panel frame" do
    assert_difference -> { @dd.paragraph_styles.count }, 1 do
      post design.override_theme_paper_size_document_design_paragraph_styles_path(@theme, @ps, @dd),
           params: { name: "body" }
    end
    assert_response :success

    # Response targets the properties_panel turbo-frame with the editor form
    assert_select "turbo-frame#properties_panel"
    assert_select "turbo-frame#properties_panel form[data-controller~='design--panel-autosave']"

    # Override carries the base attrs across
    override = @dd.paragraph_styles.find_by!(name: "body")
    assert_equal 10.0, override.font_size
    assert_equal "NotoSerifKR", override.font

    # Revert link is present (it IS a document override on an editable theme)
    assert_includes response.body, "Revert"
    assert_includes response.body, "data-turbo-method=\"delete\""
  end

  # ── Step 3: PATCH panel_update persists the field change ──

  def stub_preview
    fake = Object.new
    def fake.generate = { success: true, jpg_path: "/tmp/x.jpg", overlay_data: [], page_width: 432.0, page_height: 648.0, error: nil }
    original = Design::PreviewService.method(:new)
    Design::PreviewService.define_singleton_method(:new) { |*, **| fake }
    yield
  ensure
    Design::PreviewService.define_singleton_method(:new, original)
  end

  test "PATCH panel_update (level=document) persists font_size change and re-renders preview_frame" do
    override = @dd.paragraph_styles.create!(name: "body", font_size: 10, font: "NotoSerifKR")

    stub_preview do
      patch design.panel_update_theme_paper_size_document_design_path(
              @theme, @ps, @dd,
              level: "document", style_id: override.id
            ),
            params: { paragraph_style: { font_size: 14 } },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_includes response.media_type, "turbo-stream"
    assert_includes response.body, "preview_frame"
    assert_equal 14.0, override.reload.font_size
  end

  # ── Step 4: DELETE revert destroys the override and merged falls back to base ──

  test "DELETE revert – destroys the document override so merged_paragraph_styles falls back to base" do
    override = @dd.paragraph_styles.create!(name: "body", font_size: 99)

    # Confirm override is the preferred style before revert
    merged_before = @dd.merged_paragraph_styles.find { |s| s.name == "body" }
    assert_equal 99.0, merged_before.font_size, "merged should prefer the override"

    assert_difference -> { @dd.paragraph_styles.count }, -1 do
      delete design.revert_theme_paper_size_document_design_paragraph_style_path(
               @theme, @ps, @dd, override
             )
    end
    assert_response :success

    # Response re-renders properties_panel (not a redirect)
    assert_select "turbo-frame#properties_panel"

    # After revert, merged falls back to the base style
    @dd.paragraph_styles.reload
    merged_after = @dd.reload.merged_paragraph_styles.find { |s| s.name == "body" }
    assert_equal 10.0, merged_after.font_size, "merged should fall back to base after revert"
  end

  # ── Step 2 (system theme gate): system-theme edit is 403 ──

  test "system theme document-design edit returns 403 (ensure_theme_editable guard)" do
    system_theme = Design::Theme.create!(name: "Sys #{SecureRandom.hex(3)}", locale: "ko", user_id: nil)
    sys_ps = system_theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    sys_dd = sys_ps.document_designs.create!(doc_type: "chapter")
    get design.edit_theme_paper_size_document_design_path(system_theme, sys_ps, sys_dd)
    assert_response :forbidden
  end
end
