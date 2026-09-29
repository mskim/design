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

  test "the editor's preview section: 안내선 toggle outside #preview_frame, on by default" do
    get edit_path
    assert_response :success
    assert_select "#{TOOLBAR}[data-guides='on']"
    assert_select "#{TOOLBAR} button[data-design--preview-toolbar-target='guides'][aria-pressed='true']",
                  text: I18n.t("design.preview.guides")
    assert_select "#{TOOLBAR} turbo-frame#preview_frame[loading=lazy]" do |(frame)|
      assert_equal design.preview_theme_paper_size_document_design_path(@theme, @ps, @dd), frame["src"]
    end
    assert_select "turbo-frame#preview_frame button", 0
  end

  # The studio always previews in print mode: there is no 인쇄용 toggle, on any
  # doc type, whether or not the binding applies to it.
  test "no 인쇄용 button on any doc type" do
    %w[chapter poem title_page toc copyright blank_page front_page document_cover].each do |t|
      dd = t == "chapter" ? @dd : @ps.document_designs.create!(doc_type: t)
      get edit_path(dd)
      assert_response :success
      assert_select "#{TOOLBAR} button", 1, t
      assert_select "button[data-design--preview-toolbar-target='print']", 0, t
      assert_select "button[data-action*='togglePrint']", 0, t
      assert_no_match "인쇄용", response.body, t
    end
  end

  test "the full-page style editor has the same toolbar over the single-page preview" do
    @theme.base_paragraph_styles.create!(name: "zz_body", font_size: 10)
    get design.theme_paper_size_document_design_style_path(@theme, @ps, @dd, "zz_body")
    assert_response :success
    assert_select "#{TOOLBAR} turbo-frame#preview_frame[src*='preview_mode=single']"
    assert_select "#{TOOLBAR} button[data-design--preview-toolbar-target='guides']"
    assert_select "#{TOOLBAR} button[data-design--preview-toolbar-target='print']", 0
  end
end
