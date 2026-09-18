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
end
