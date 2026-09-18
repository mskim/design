require "test_helper"

# Renders Design::Views::Sidebar directly (no controller). Route helpers are
# stubbed on the component the same way shell_test.rb stubs them on Shell.
class Design::SidebarTest < ActiveSupport::TestCase
  class FakeHelpers
    def theme_path(theme, **q) = "/themes/#{theme.id}" + (q.empty? ? "" : "?paper_size_id=#{q[:paper_size_id]}")
    def new_theme_paper_size_path(theme) = "/themes/#{theme.id}/paper_sizes/new"
    def edit_theme_paper_size_path(theme, ps) = "/themes/#{theme.id}/paper_sizes/#{ps.id}/edit"
    def generate_sizes_theme_path(theme) = "/themes/#{theme.id}/generate_sizes"
    def edit_theme_paper_size_document_design_path(theme, ps, dd) = "/themes/#{theme.id}/paper_sizes/#{ps.id}/document_designs/#{dd.id}/edit"
    def edit_theme_table_style_path(theme, ts) = "/themes/#{theme.id}/table_styles/#{ts.id}/edit"
    def form_authenticity_token = "tok"
  end

  setup do
    sign_in :david # Design.current_user → editable_by? true for a theme owned by david
    @theme = Design::Theme.create!(name: "Sb #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ps    = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @other = @theme.paper_sizes.create!(size_name: "A4", width_mm: 210, height_mm: 297)
  end

  def render_sidebar(theme: @theme, paper_size: @ps, **opts)
    component = Design::Views::Sidebar.new(theme: theme, paper_size: paper_size, **opts)
    component.define_singleton_method(:helpers) { FakeHelpers.new }
    Nokogiri::HTML.fragment(component.call)
  end

  test "renders one option per theme with the current theme selected" do
    doc = render_sidebar
    select = doc.at_css("select[data-sidebar='theme']")
    assert select, "theme select missing"
    assert_equal Design::Theme.count, select.css("option").size
    selected = select.at_css("option[selected]")
    assert_equal @theme.name, selected.text
    assert_equal "/themes/#{@theme.id}", selected["data-url"]
  end

  test "renders one option per paper size with the current size selected" do
    doc = render_sidebar
    select = doc.at_css("select[data-sidebar='size']")
    assert_equal 2, select.css("option").size
    assert_equal @ps.display_name, select.at_css("option[selected]").text
  end

  test "size options default to the theme overview for that size" do
    doc = render_sidebar
    option = doc.at_css("select[data-sidebar='size'] option:not([selected])")
    assert_equal "/themes/#{@theme.id}?paper_size_id=#{@other.id}", option["data-url"]
  end

  test "size options use the size_url lambda when given" do
    doc = render_sidebar(size_url: ->(ps) { "/custom/#{ps.id}" })
    urls = doc.css("select[data-sidebar='size'] option").map { |o| o["data-url"] }
    assert_equal [ "/custom/#{@ps.id}", "/custom/#{@other.id}" ], urls
  end

  test "both selects are wired to the navigate-select controller" do
    doc = render_sidebar
    assert_equal 2, doc.css("select[data-controller='design--navigate-select'][data-action='change->design--navigate-select#change']").size
  end

  test "renders without a paper size" do
    doc = render_sidebar(paper_size: nil)
    assert doc.at_css("select[data-sidebar='theme']")
    assert_nil doc.at_css("select[data-sidebar='size'] option[selected]")
  end

  # --- matter groups ---

  def seed_designs
    @chapter = @ps.document_designs.create!(doc_type: "chapter")
    @title   = @ps.document_designs.create!(doc_type: "title_page")
    @front   = @ps.document_designs.create!(doc_type: "front_page")
  end

  test "renders matter groups cover-first, omitting empty groups" do
    seed_designs
    doc = render_sidebar
    summaries = doc.css("details > summary").map { |s| s.text.strip }
    assert_equal [ I18n.t("design.themes.cover"), I18n.t("design.themes.frontmatter"), I18n.t("design.themes.bodymatter"),
                   I18n.t("design.sidebar.table_styles") ], summaries
  end

  test "every group is open and each leaf links to the design editor" do
    seed_designs
    doc = render_sidebar
    assert_equal 4, doc.css("details[open]").size, "all four groups should be open"
    link = doc.at_css("a[href='/themes/#{@theme.id}/paper_sizes/#{@ps.id}/document_designs/#{@chapter.id}/edit']")
    assert link, "chapter leaf missing"
    assert_equal I18n.t("design.doc_types.chapter"), link.text.strip
    assert_equal I18n.t("design.doc_types.chapter"), link["title"]
  end

  test "highlights only the current document design" do
    seed_designs
    doc = render_sidebar(current: { kind: :document_design, id: @chapter.id })
    current = doc.css("[aria-current='page']")
    assert_equal 1, current.size
    assert_includes current.first.text, I18n.t("design.doc_types.chapter")
    assert_includes current.first["class"], "bg-slate-900", "active leaf should carry the active classes"
  end

  test "nothing is highlighted without current" do
    seed_designs
    doc = render_sidebar
    assert_empty doc.css("[aria-current='page']")
  end

  test "renders Korean labels with no translation-missing leftovers" do
    seed_designs
    html = I18n.with_locale(:ko) { render_sidebar.to_html }
    # Literal Korean, not I18n.t round-trips: a deleted key would make I18n.t return
    # "Translation missing: ko.…" on both sides and the assertion could never fail.
    refute_match(/translation missing/i, html)
    assert_includes html, "판형"          # design.sidebar.size
    assert_includes html, "판형 설정"     # design.sidebar.size_settings
    assert_includes html, "장"            # design.doc_types.chapter
    refute_includes html, "Size settings" # the en string must not leak
  end

  # --- size links + table styles ---

  test "editable theme shows new-size, size-settings links and the generate button" do
    doc = render_sidebar
    assert doc.at_css("a[href='/themes/#{@theme.id}/paper_sizes/new']"), "new size link"
    assert doc.at_css("a[href='/themes/#{@theme.id}/paper_sizes/#{@ps.id}/edit']"), "size settings link"
    assert doc.at_css("form[action='/themes/#{@theme.id}/generate_sizes']"), "generate sizes form"
  end

  test "read-only theme hides size links and the generate button" do
    system_theme = Design::Theme.create!(name: "Sys #{SecureRandom.hex(3)}", locale: "ko") # user_id nil
    ps = system_theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    Design.config.authoring = false
    doc = render_sidebar(theme: system_theme, paper_size: ps)
    assert_nil doc.at_css("a[href$='/paper_sizes/new']")
    assert_nil doc.at_css("form[action$='/generate_sizes']")
  end

  # Editor actions answer 403 on a read-only theme (ApplicationController#ensure_theme_editable),
  # so the rail lists the structure as plain text rather than linking to editors it can't open.
  test "read-only theme lists designs and table styles as text, not editor links" do
    system_theme = Design::Theme.create!(name: "Sys #{SecureRandom.hex(3)}", locale: "ko") # user_id nil
    ps = system_theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.create!(doc_type: "chapter")
    ts = system_theme.table_styles.find_by!(name: "grid") # seeded by Theme#seed_default_styles on create
    Design.config.authoring = false
    doc = render_sidebar(theme: system_theme, paper_size: ps)
    assert_nil doc.at_css("a[href$='/document_designs/#{dd.id}/edit']"), "design leaf must not link to the editor"
    assert_nil doc.at_css("a[href*='/table_styles/']"), "table style leaf must not link to the editor"
    leaf = doc.css("li > span").find { |s| s.text.strip == I18n.t("design.doc_types.chapter") }
    assert leaf, "doc_type label should still be listed (as a span)"
    assert_equal I18n.t("design.doc_types.chapter"), leaf["title"]
    assert doc.css("li > span").any? { |s| s.text.strip == ts.name.capitalize }, "table style label should still be listed"
    assert_empty doc.css("[aria-current='page']")
  end

  test "size settings link is highlighted for current kind paper_size" do
    doc = render_sidebar(current: { kind: :paper_size })
    current = doc.css("[aria-current='page']")
    assert_equal 1, current.size
    assert_equal "/themes/#{@theme.id}/paper_sizes/#{@ps.id}/edit", current.first["href"]
  end

  test "table styles group lists the theme's table styles and highlights the current one" do
    ts = @theme.table_styles.find_by!(name: "grid") # seeded by Theme#seed_default_styles on create
    doc = render_sidebar(current: { kind: :table_style, id: ts.id })
    summary = doc.css("details > summary").find { |s| s.text.strip == I18n.t("design.sidebar.table_styles") }
    assert summary, "table styles group missing"
    link = doc.at_css("a[href='/themes/#{@theme.id}/table_styles/#{ts.id}/edit']")
    assert_equal "page", link["aria-current"]
  end

  test "table styles group is omitted when the theme has none" do
    @theme.table_styles.destroy_all # Theme#seed_default_styles seeds them on create
    doc = render_sidebar
    refute_includes doc.css("details > summary").map { |s| s.text.strip }, I18n.t("design.sidebar.table_styles")
  end
end
