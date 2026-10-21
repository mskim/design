require "test_helper"

# Book designs (a book's own copy of a starter, owned by the host app) never show up
# in the studio: not listed, not reachable by id, not in the sidebar's theme picker.
class Design::BookDesignScopingTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @starter = Design::Theme.create!(name: "Starter #{SecureRandom.hex(3)}", locale: "ko", user: users(:david))
    @ps = @starter.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "chapter")

    @book_design = Design::Theme.create!(name: "BookCopy #{SecureRandom.hex(3)}", locale: "ko", book_id: 7)
    @bd_ps = @book_design.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @bd_dd = @bd_ps.document_designs.create!(doc_type: "chapter")
  end

  test "the themes index lists no book design" do
    get design.themes_path
    assert_response :success
    assert_not_includes response.body, @book_design.name
    assert_includes response.body, @starter.name
  end

  test "a book design's theme pages are not found" do
    get design.theme_path(@book_design)
    assert_response :not_found

    get design.edit_theme_path(@book_design)
    assert_response :not_found

    get design.edit_theme_paper_size_document_design_path(@book_design, @bd_ps, @bd_dd)
    assert_response :not_found
  end

  test "the sidebar's theme list excludes book designs" do
    get design.theme_path(@starter, paper_size_id: @ps.id)
    assert_response :success
    assert_select "aside select[data-sidebar='theme'] option[value=?]", @starter.id.to_s
    assert_select "aside select[data-sidebar='theme'] option[value=?]", @book_design.id.to_s, false
  end
end
