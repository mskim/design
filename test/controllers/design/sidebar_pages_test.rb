require "test_helper"

# One test per page that gets the studio sidebar (spec: every page inside a theme).
class Design::SidebarPagesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @theme = Design::Theme.create!(name: "Rail #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ps    = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @a4    = @theme.paper_sizes.create!(size_name: "A4", width_mm: 210, height_mm: 297)
    @dd    = @ps.document_designs.create!(doc_type: "chapter")
  end

  test "theme overview renders the sidebar and no pill bar" do
    get design.theme_path(@theme, paper_size_id: @ps.id)
    assert_response :success
    assert_select "aside select[data-sidebar='size'] option[selected]", text: @ps.display_name
    assert_select "aside a[href=?]", design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
    # `aside + main` is the shell's content region; the design layout wraps the whole
    # studio in an outer <main>, so a bare `main` selector would also reach the rail.
    assert_select "aside + main a.rounded-full", false, "pill bar should be gone"
    assert_select "aside + main a[href=?]", design.new_theme_paper_size_path(@theme), false
  end

  test "theme overview size options point at the overview for each size" do
    get design.theme_path(@theme, paper_size_id: @ps.id)
    assert_select "aside select[data-sidebar='size'] option[data-url=?]", design.theme_path(@theme, paper_size_id: @a4.id)
  end

  test "design editor highlights its design and switches size to the same doc_type" do
    a4_chapter = @a4.document_designs.create!(doc_type: "chapter")
    get design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
    assert_response :success
    assert_select "aside a[aria-current='page'][href=?]", design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
    assert_select "aside option[data-url=?]", design.edit_theme_paper_size_document_design_path(@theme, @a4, a4_chapter)
  end

  test "design editor falls back to the overview when the other size lacks that doc_type" do
    get design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
    assert_select "aside option[data-url=?]", design.theme_path(@theme, paper_size_id: @a4.id)
  end

  test "paragraph style edit page highlights the parent design" do
    style = @dd.paragraph_styles.create!(name: "body")
    get design.panel_theme_paper_size_document_design_path(@theme, @ps, @dd, level: "document", style_id: style.id)
    assert_response :success
    assert_select "aside a[aria-current='page'][href=?]", design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd)
  end

  test "table style editor highlights the table style; size select changes tree context only" do
    ts = @theme.table_styles.find_by!(name: "grid")
    get design.edit_theme_table_style_path(@theme, ts)
    assert_response :success
    assert_select "aside a[aria-current='page'][href=?]", design.edit_theme_table_style_path(@theme, ts)
    assert_select "aside option[data-url=?]", design.theme_path(@theme, paper_size_id: @a4.id)
  end

  test "paper size edit highlights size settings and switches to the other size's edit page" do
    get design.edit_theme_paper_size_path(@theme, @ps)
    assert_response :success
    assert_select "aside a[aria-current='page'][href=?]", design.edit_theme_paper_size_path(@theme, @ps)
    assert_select "aside option[data-url=?]", design.edit_theme_paper_size_path(@theme, @a4)
  end

  test "new paper size page renders the rail at the default size with nothing highlighted" do
    get design.new_theme_paper_size_path(@theme)
    assert_response :success
    assert_select "aside select[data-sidebar='size']"
    assert_select "aside [aria-current='page']", false
  end
end
