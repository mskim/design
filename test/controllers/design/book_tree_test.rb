require "test_helper"

# The theme page grid shows only the book-tree (sidebar) groups that are open.
# The open set is a per-browser cookie (design_tree_open) written by
# design--book-tree; with no cookie only 본문 (bodymatter) is open.
class Design::BookTreeTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @theme = Design::Theme.create!(name: "Tree #{SecureRandom.hex(3)}", locale: "ko", user: users(:david))
    @ps    = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @title   = @ps.document_designs.create!(doc_type: "title_page")
    @chapter = @ps.document_designs.create!(doc_type: "chapter")
    @epilogue = @ps.document_designs.create!(doc_type: "epilogue")
  end

  def show(cookie: nil)
    # A raw Cookie header, as the browser sends what design--book-tree wrote
    # (encodeURIComponent: "," → "%2C"); rack-test's jar mangles such values.
    headers = cookie.nil? ? {} : { "Cookie" => "#{Design::Views::BookTree::COOKIE}=#{cookie}" }
    stub_preview_service { get design.theme_path(@theme, paper_size_id: @ps.id), headers: headers }
    assert_response :success
  end

  def open_groups = css_select("aside details[data-matter][open]").map { |d| d["data-matter"] }
  def visible_sections = css_select("[data-doc-grid] section[data-matter]:not([hidden])").map { |s| s["data-matter"] }
  def hidden_sections = css_select("[data-doc-grid] section[data-matter][hidden]").map { |s| s["data-matter"] }
  def hint = css_select("[data-doc-grid-empty]").first

  test "no cookie: only bodymatter is open in the tree and visible in the grid" do
    show
    assert_equal %w[bodymatter], open_groups
    assert_equal %w[bodymatter], visible_sections
    assert_equal %w[frontmatter rearmatter], hidden_sections.sort, "other sections are rendered, hidden"
    assert hint.key?("hidden"), "hint hidden while a section shows"
  end

  test "cookie frontmatter,bodymatter opens and shows both" do
    show(cookie: "frontmatter%2Cbodymatter")
    assert_equal %w[frontmatter bodymatter], open_groups
    assert_equal %w[frontmatter bodymatter], visible_sections
    assert_equal %w[rearmatter], hidden_sections
  end

  test "a junk cookie falls back to the default" do
    show(cookie: "bogus%2C%3Cscript%3E")
    assert_equal %w[bodymatter], open_groups
    assert_equal %w[bodymatter], visible_sections
  end

  test "cookie rearmatter shows only the rear section" do
    show(cookie: "rearmatter")
    assert_equal %w[rearmatter], visible_sections
    assert hint.key?("hidden")
  end

  test "an empty cookie hides every section and shows the hint" do
    show(cookie: "")
    assert_empty open_groups
    assert_empty visible_sections
    assert_equal 3, hidden_sections.size
    refute hint.key?("hidden"), "hint shows when nothing is visible"
    assert_equal I18n.t("design.themes.tree_hint"), hint.text.strip
  end

  test "an open set covering only empty groups shows the hint" do
    show(cookie: "cover")
    assert_empty visible_sections
    refute hint.key?("hidden")
  end

  test "the sidebar carries the book-tree controller and each matter group toggles it" do
    show
    assert_select "aside nav[data-controller~='design--book-tree'][data-design--book-tree-open-value='bodymatter']"
    assert_select "aside details[data-matter]", count: 3
    assert_select "aside details[data-matter][data-action='toggle->design--book-tree#toggle']", count: 3
  end

  test "the doc grid is four across on wide screens" do
    show
    grid = css_select("[data-doc-grid] section .grid").first
    assert_includes grid["class"].split, "lg:grid-cols-4"
    refute_includes grid["class"].split, "lg:grid-cols-5"
  end

  test "editor page for a frontmatter design opens its group too" do
    get design.edit_theme_paper_size_document_design_path(@theme, @ps, @title)
    assert_response :success
    assert_equal %w[frontmatter bodymatter], open_groups
    assert_select "aside details[data-matter='frontmatter'][data-pinned-open]"
    assert_select "aside a[aria-current='page'][href=?]", design.edit_theme_paper_size_document_design_path(@theme, @ps, @title)
  end

  test "the table styles group is always open and not a matter group" do
    show(cookie: "")
    assert_select "aside details[open]:not([data-matter]) summary", text: I18n.t("design.sidebar.table_styles")
  end

  private

  def stub_preview_service
    fake = Object.new
    fake.define_singleton_method(:generate) { { success: false } }
    original = Design::PreviewService.method(:new)
    Design::PreviewService.define_singleton_method(:new) { |*, **| fake }
    yield
  ensure
    Design::PreviewService.singleton_class.send(:define_method, :new, original)
  end
end
