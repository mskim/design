require "test_helper"

# End-to-end integration test for the 단락정의 (typography) style editor flow.
# Exercises: merged-styles list → name-keyed style panel → field save → "+"
# marker → field revert, against a CUSTOM (editable) theme, signed in as david.
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

  test "list → panel → field save → + marker → field revert" do
    get design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd, tab: "typography")
    assert_response :success
    assert_select "[data-ruby-ui--tabs-active-value='typography']"
    assert_select "[data-style-row='body'] a[href=?]", design.theme_paper_size_document_design_style_path(@theme, @ps, @dd, "body")
    assert_select "[data-style-row='body'] [data-changed-marker]", count: 0

    get design.theme_paper_size_document_design_style_path(@theme, @ps, @dd, "body"), headers: { "Turbo-Frame" => "properties_panel" }
    assert_select "form[data-controller~='design--style-autosave']"

    stub_preview do
      patch design.field_theme_paper_size_document_design_style_path(@theme, @ps, @dd, "body"),
            params: { field: "font_size", value: "14" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    assert_equal 14, @dd.paragraph_styles.find_by!(name: "body").font_size.to_i

    get design.properties_panel_theme_paper_size_document_design_path(@theme, @ps, @dd, tab: "typography")
    assert_select "[data-style-row='body'] [data-changed-marker]"

    stub_preview do
      delete design.field_theme_paper_size_document_design_style_path(@theme, @ps, @dd, "body"),
             params: { field: "font_size" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_nil @dd.paragraph_styles.find_by(name: "body")
    assert_equal 10, @dd.reload.merged_paragraph_styles.find { |s| s.name == "body" }.font_size.to_i
  end

  def stub_preview
    fake = Object.new
    def fake.generate = { success: true, jpg_path: "/tmp/x.jpg", overlay_data: [], page_width: 432.0, page_height: 648.0, error: nil }
    original = Design::PreviewService.method(:new)
    Design::PreviewService.define_singleton_method(:new) { |*, **| fake }
    yield
  ensure
    Design::PreviewService.define_singleton_method(:new, original)
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
