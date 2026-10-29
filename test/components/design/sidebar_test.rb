require "test_helper"

# Renders Design::Views::Sidebar directly (no controller). Route helpers are
# stubbed on the component the same way shell_test.rb stubs them on Shell.
class Design::SidebarTest < ActiveSupport::TestCase
  include TypedTableStyles

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

  test "the Korean book-matter names are 표지 / 머리 / 본문 / 꼬리" do
    I18n.with_locale(:ko) do
      assert_equal %w[표지 머리 본문 꼬리],
                   %w[cover frontmatter bodymatter rearmatter].map { |k| I18n.t("design.themes.#{k}") }
    end
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

  test "a theme with no paper sizes shows the theme select and the new-size link, no size select" do
    bare = Design::Theme.create!(name: "Bare #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    doc = render_sidebar(theme: bare, paper_size: nil)
    assert doc.at_css("select[data-sidebar='theme']")
    assert_nil doc.at_css("select[data-sidebar='size']"), "no size select without sizes"
    assert doc.at_css("a[href='/themes/#{bare.id}/paper_sizes/new']"), "new size link"
  end

  # --- matter groups ---

  def seed_designs
    @chapter = @ps.document_designs.create!(doc_type: "chapter")
    @title   = @ps.document_designs.create!(doc_type: "title_page")
    @front   = @ps.document_designs.create!(doc_type: "front_page")
  end

  def section_labels(doc) = doc.css(".book-tree__section .book-tree__section-label").map { |s| s.text.strip }
  def open_matters(doc) = doc.css("section[data-matter]:has(> .book-tree__row > .book-tree__toggle[aria-expanded='true'])").map { |s| s["data-matter"] }

  test "renders matter sections cover-first, omitting empty ones, then table styles" do
    seed_designs
    doc = render_sidebar
    assert_equal [ I18n.t("design.themes.cover"), I18n.t("design.themes.frontmatter"), I18n.t("design.themes.bodymatter"),
                   I18n.t("design.sidebar.table_styles") ], section_labels(doc)
  end

  test "the tree is book_write's: 책 전체 alone on top, then sections each with a chevron fold toggle" do
    seed_designs
    doc = render_sidebar
    tree = doc.at_css("div.book-tree.studio-tree")
    assert tree, "book tree missing"
    first = tree.element_children.first
    assert_equal "ul", first.name
    assert_includes first["class"].split, "studio-tree__book"
    whole = first.at_css("li.book-tree__item > .book-tree__row > a.book-tree__link")
    assert_equal I18n.t("design.sidebar.whole_book"), whole.text.strip
    assert_equal "/themes/#{@theme.id}?paper_size_id=#{@ps.id}", whole["href"]
    tree.css("section.book-tree__section").each do |section|
      toggle = section.at_css("> .book-tree__row.book-tree__row--section > button.book-tree__toggle[type='button']")
      assert toggle, "section toggle missing"
      assert_equal "design--book-tree#toggle", toggle["data-action"]
      assert toggle.at_css(".book-tree__section-label")
      assert toggle.at_css(".book-tree__chevron[aria-hidden='true']")
      assert_equal I18n.t("design.sidebar.toggle"), toggle.at_css(".sr-only").text
      assert section.at_css("> ul.book-tree__items"), "section list missing"
    end
  end

  test "body designs are listed in reading order" do
    %w[poem chapter part_cover].each { |t| @ps.document_designs.create!(doc_type: t) }
    doc = render_sidebar
    labels = doc.css("section[data-matter='bodymatter'] .book-tree__link").map { |a| a.text.strip }
    assert_equal %w[part_cover chapter poem].map { |t| I18n.t("design.doc_types.#{t}") }, labels
  end

  # No request (bare render) → no cookie → the default: only 본문 open. The
  # table styles section is not a matter group and is always open.
  test "only bodymatter and table styles are open by default; each leaf links to the design editor" do
    seed_designs
    doc = render_sidebar
    assert_equal %w[bodymatter], open_matters(doc)
    assert_equal %w[cover frontmatter bodymatter], doc.css("section[data-matter]").map { |d| d["data-matter"] }
    table = doc.at_css("section.book-tree__section:not([data-matter])")
    assert_equal "true", table.at_css(".book-tree__toggle")["aria-expanded"], "table styles section stays open"
    link = doc.at_css("a.book-tree__link[href='/themes/#{@theme.id}/paper_sizes/#{@ps.id}/document_designs/#{@chapter.id}/edit']")
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
    assert_includes current.first["class"].split, "is-current", "current leaf carries book_write's is-current"
    assert_equal 1, doc.css(".is-current").size
  end

  test "책 전체 is current on the theme overview (kind :theme), and size settings is not" do
    doc = render_sidebar(current: { kind: :theme })
    current = doc.css("[aria-current='page']")
    assert_equal 1, current.size
    assert_equal I18n.t("design.sidebar.whole_book"), current.first.text.strip
    assert_includes current.first["class"].split, "is-current"
  end

  test "the section holding the current design is open (pinned) so its leaf shows" do
    seed_designs
    doc = render_sidebar(current: { kind: :document_design, id: @title.id })
    assert_equal %w[frontmatter bodymatter], open_matters(doc)
    assert doc.at_css("section[data-matter='frontmatter'][data-pinned-open]")
    assert_nil doc.at_css("section[data-matter='bodymatter'][data-pinned-open]")
  end

  test "no tree sections and no 책 전체 without a paper size" do
    doc = render_sidebar(paper_size: nil)
    assert_nil doc.at_css(".studio-tree__book")
    assert_empty doc.css("section[data-matter]")
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
    assert_includes html, "책 전체"       # design.sidebar.whole_book
    assert_includes html, "열기/닫기"     # design.sidebar.toggle
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
    leaf = doc.css("span.book-tree__link").find { |s| s.text.strip == I18n.t("design.doc_types.chapter") }
    assert leaf, "doc_type label should still be listed (as a span)"
    assert_equal I18n.t("design.doc_types.chapter"), leaf["title"]
    assert doc.css("span.book-tree__link").any? { |s| s.text.strip == ts.name.capitalize }, "table style label should still be listed"
    assert_empty doc.css("[aria-current='page']")
    assert_equal "/themes/#{system_theme.id}?paper_size_id=#{ps.id}", doc.at_css("a.book-tree__link")["href"],
                 "책 전체 still links: the theme overview is open on a read-only theme"
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
    assert_includes section_labels(doc), I18n.t("design.sidebar.table_styles"), "table styles section missing"
    link = doc.at_css("a[href='/themes/#{@theme.id}/table_styles/#{ts.id}/edit']")
    assert_equal "page", link["aria-current"]
  end

  test "table styles group lists only the defaults, not a document type's own" do
    add_table_style_doc_type!
    typed = @theme.table_styles.create!(name: "zebra", doc_type: "foreword")
    doc = render_sidebar
    assert_equal 5, doc.css("a[href*='/table_styles/']").size
    assert_nil doc.at_css("a[href='/themes/#{@theme.id}/table_styles/#{typed.id}/edit']")
  end

  test "table styles group is omitted when the theme has none" do
    @theme.table_styles.destroy_all # Theme#seed_default_styles seeds them on create
    doc = render_sidebar
    refute_includes section_labels(doc), I18n.t("design.sidebar.table_styles")
  end
end
