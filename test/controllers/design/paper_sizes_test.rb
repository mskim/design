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

  test "create with valid params adds a size, auto-generates docs, and redirects" do
    assert_difference -> { @theme.paper_sizes.count }, 1 do
      post design.theme_paper_sizes_path(@theme),
           params: { paper_size: { size_name: "46판", width_mm: 127, height_mm: 188 } }
    end
    created = @theme.paper_sizes.order(:created_at).last
    assert_response :redirect
    assert_equal Design::DocumentDesign::ALL_DOC_TYPES.size, created.document_designs.count,
                 "create should seed every doc type via PaperSizeSeeder"
  end

  test "create with invalid params re-renders 422 with errors" do
    assert_no_difference -> { @theme.paper_sizes.count } do
      post design.theme_paper_sizes_path(@theme), params: { paper_size: { size_name: "", width_mm: 0 } }
    end
    assert_response :unprocessable_entity
    assert_select "div", text: /can.t be blank|greater than/i
  end
end
