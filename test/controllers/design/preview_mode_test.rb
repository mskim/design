require "test_helper"

# The design editor scrolls all pages; the style edit pages show page 1 only. The
# mode travels as ?preview_mode=single on the frame src and as the style panel
# form's preview-mode value, so a save re-renders the preview in the same mode.
class Design::PreviewModeTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @theme = Design::Theme.create!(name: "Mode #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "chapter")
    @style = @dd.paragraph_styles.create!(name: "body")
  end

  test "design editor frame src has no preview_mode (scroll)" do
    get design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
    assert_select "turbo-frame#preview_frame[src]" do |frames|
      refute_includes frames.first["src"], "preview_mode"
    end
    assert_select "input[name=preview_mode]", false
  end

  test "paragraph style edit page requests a single-page preview and saves in single mode" do
    get design.theme_paper_size_document_design_style_path(@theme, @ps, @dd, "body")
    assert_response :success
    assert_select "turbo-frame#preview_frame[src*='preview_mode=single']"
    assert_select "form[data-design--style-autosave-preview-mode-value='single']"
  end

  test "embedded panel (turbo-frame request) carries the incoming preview_mode" do
    get design.theme_paper_size_document_design_style_path(@theme, @ps, @dd, "body", preview_mode: "single"),
        headers: { "Turbo-Frame" => "properties_panel" }
    assert_response :success
    assert_select "form[data-design--style-autosave-preview-mode-value='single']"
    get design.theme_paper_size_document_design_style_path(@theme, @ps, @dd, "body"),
        headers: { "Turbo-Frame" => "properties_panel" }
    assert_response :success
    assert_select "form[data-design--style-autosave-preview-mode-value]", false
  end
end
