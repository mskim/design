require "test_helper"

class Design::PaperSizesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david   # admin, can_design?
    @theme = Design::Theme.create!(name: "Owned #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
  end

  test "new renders the page-size form with identity + dimension fields" do
    get design.new_theme_paper_size_path(@theme)
    assert_response :success
    assert_select "body.design-studio"
    assert_select "input[name=?]", "paper_size[size_name]"
    assert_select "input[name=?]", "paper_size[width_mm]"
    assert_select "input[name=?]", "paper_size[height_mm]"
  end

  test "edit renders in the design layout with identity + margin fields + base styles entry" do
    get design.edit_theme_paper_size_path(@theme, @ps)
    assert_response :success
    assert_select "body.design-studio"
    assert_select "input[name=?]", "paper_size[size_name]"
    assert_select "input[name=?]", "paper_size[left_margin_mm]"
  end

  test "update persists and redirects" do
    patch design.theme_paper_size_path(@theme, @ps), params: { paper_size: { left_margin_mm: 30 } }
    assert_response :redirect
    assert_equal 30.0, @ps.reload.left_margin_mm
  end
end
