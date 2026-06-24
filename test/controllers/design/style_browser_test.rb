require "test_helper"

class Design::StyleBrowserTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @theme = Design::Theme.create!(name: "Br #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
  end

  test "renders the browser with four cascading auto-submit filters" do
    get design.style_browser_path
    assert_response :success
    assert_select "body.design-studio"
    assert_select "form[data-controller~='design--auto-submit']"
    assert_select "select[name=?]", "theme"
    assert_select "select[name=?]", "size"
    assert_select "select[name=?]", "doc_type"
    assert_select "select[name=?]", "style_name"
    assert_select "select[data-action~='change->design--auto-submit#submit']", minimum: 4
  end

  test "lists base styles and marks document-design overrides with a badge" do
    dd = @ps.document_designs.create!(doc_type: "chapter")
    # an override at the doc-design level
    base = @theme.base_paragraph_styles.create!(name: "body", font: "Noto", font_size: 10)
    dd.paragraph_styles.create!(name: "body", font: "Noto", font_size: 12) # override
    get design.style_browser_path(theme: @theme.name, size: @ps.size_name, doc_type: "chapter")
    assert_response :success
    assert_includes response.body, "body"          # style name shown
    assert_select "td", text: /#{Regexp.escape(I18n.t("design.style_browser.override"))}/  # override marker present
  end

  test "renders a color swatch for a style with text_color" do
    dd = @ps.document_designs.create!(doc_type: "chapter")
    @theme.base_paragraph_styles.create!(name: "title", text_color: "#112233", font_size: 20)
    get design.style_browser_path(theme: @theme.name, size: @ps.size_name, doc_type: "chapter")
    assert_includes response.body, "#112233"
  end

  test "base row Edit link points at the theme-level style edit; override row at the doc-design level" do
    dd = @ps.document_designs.create!(doc_type: "chapter")
    base = @theme.base_paragraph_styles.create!(name: "body", font_size: 10)
    ovr_dd = @ps.document_designs.create!(doc_type: "toc")
    ovr_dd.paragraph_styles.create!(name: "body", font_size: 12)
    get design.style_browser_path # all-doc-types view → base rows + override rows
    # base "body" row → theme-level edit
    assert_select "a[href=?]", design.edit_theme_theme_paragraph_style_path(@theme, base)
    # override row → doc-design-level edit
    ovr = ovr_dd.paragraph_styles.find_by(name: "body")
    assert_select "a[href=?]", design.edit_theme_paper_size_document_design_paragraph_style_path(@theme, @ps, ovr_dd, ovr)
  end

  test "renders a registered host action in the per-row slot" do
    Design.config.actions.for(:style_browser_row) { |row| [ { label: "PDF", path: "/x.pdf" } ] }
    @ps.document_designs.create!(doc_type: "chapter")
    @theme.base_paragraph_styles.create!(name: "body", font_size: 10)
    get design.style_browser_path
    assert_select "a[href='/x.pdf']", text: "PDF"
  ensure
    Design.config.actions.for(:style_browser_row) { nil }   # reset (registrations is private)
  end
end
