require "test_helper"

# The theme show page renders a chip per doc_type. For an editable theme the chip
# is a link to the doc_type editor; otherwise it's plain text. System (baseline)
# themes are always read-only in book_write — their chips are plain text.
class Design::ThemesShowEditableChipsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david # admin (can_design?)
    @theme = Design::Theme.create!(name: "Sys #{SecureRandom.hex(3)}", locale: "ko") # system (user_id nil)
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "copyright")
  end

  test "system theme doc_type chips are read-only" do
    get "/design/themes/#{@theme.id}"
    assert_response :success
    assert @theme.system?
    assert_select "a[href=?]", design.edit_theme_paper_size_document_design_path(@theme, @ps, @dd), count: 0
  end

  test "custom theme doc_type chips are editable links for a designer" do
    custom = Design::Theme.create!(name: "Cust #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    ps = custom.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    dd = ps.document_designs.create!(doc_type: "copyright")

    get "/design/themes/#{custom.id}"
    assert_response :success
    assert_select "a[href=?]", design.edit_theme_paper_size_document_design_path(custom, ps, dd)
  end
end
