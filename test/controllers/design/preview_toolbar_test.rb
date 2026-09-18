require "test_helper"

class Design::PreviewToolbarTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @theme = Design::Theme.create!(name: "PT #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "chapter")
  end

  TOOLBAR = "[data-controller~='design--preview-toolbar']"

  def edit_path(dd = @dd) = design.edit_theme_paper_size_document_design_path(@theme, @ps, dd)

  test "the editor's preview section: toggles outside #preview_frame; 안내선 on, 인쇄용 off by default" do
    get edit_path
    assert_response :success
    assert_select "#{TOOLBAR}[data-guides='on']" do |(section)|
      assert_equal design.preview_theme_paper_size_document_design_path(@theme, @ps, @dd),
                   section["data-design--preview-toolbar-preview-url-value"]
    end
    assert_select "#{TOOLBAR} button[data-design--preview-toolbar-target='guides'][aria-pressed='true']",
                  text: I18n.t("design.preview.guides")
    assert_select "#{TOOLBAR} button[data-design--preview-toolbar-target='print'][aria-pressed='false']:not([disabled]):not([title])",
                  text: I18n.t("design.preview.print")
    assert_select "#{TOOLBAR} turbo-frame#preview_frame[src][loading=lazy]"
    assert_select "turbo-frame#preview_frame button", 0
  end

  test "the print cookie presses 인쇄용" do
    cookies["design_preview_print"] = "1"
    get edit_path
    assert_select "button[data-design--preview-toolbar-target='print'][aria-pressed='true']"
  end

  test "인쇄용 is disabled with the reason on doc types the engine never binds" do
    cookies["design_preview_print"] = "1"
    %w[title_page poem].each do |t|
      get edit_path(@ps.document_designs.create!(doc_type: t))
      assert_select "button[data-design--preview-toolbar-target='print'][disabled][aria-pressed='false'][title=?]",
                    I18n.t("design.preview.print_unavailable")
    end
  end

  test "the full-page style editor has the same toolbar over the single-page preview" do
    @theme.base_paragraph_styles.create!(name: "zz_body", font_size: 10)
    get design.theme_paper_size_document_design_style_path(@theme, @ps, @dd, "zz_body")
    assert_response :success
    assert_select "#{TOOLBAR}[data-design--preview-toolbar-preview-url-value*='preview_mode=single']"
    assert_select "#{TOOLBAR} turbo-frame#preview_frame[src*='preview_mode=single']"
    assert_select "#{TOOLBAR} button[data-design--preview-toolbar-target='print'][aria-pressed='false']:not([disabled])"
    cookies["design_preview_print"] = "1"
    get design.theme_paper_size_document_design_style_path(@theme, @ps, @dd, "zz_body")
    assert_select "#{TOOLBAR} button[data-design--preview-toolbar-target='print'][aria-pressed='true']:not([disabled])"
  end
end
