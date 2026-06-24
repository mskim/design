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

  test "update round-trips identity + margin fields" do
    patch design.theme_paper_size_path(@theme, @ps),
          params: { paper_size: { local_name: "신국판", width_mm: 150, top_margin_mm: 22 } }
    assert_response :redirect
    @ps.reload
    assert_equal "신국판", @ps.local_name
    assert_equal 150.0, @ps.width_mm
    assert_equal 22.0, @ps.top_margin_mm
  end

  test "update marks an edited generatable field as overridden" do
    patch design.theme_paper_size_path(@theme, @ps), params: { paper_size: { body_line_count: 99 } }
    assert @ps.reload.overridden?(:body_line_count), "edited generatable field must be marked overridden"
  end

  test "update with invalid params re-renders 422" do
    patch design.theme_paper_size_path(@theme, @ps), params: { paper_size: { size_name: "" } }
    assert_response :unprocessable_entity
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

  test "destroy removes the size and cascades its document designs" do
    other = @theme.paper_sizes.create!(size_name: "46판", width_mm: 127, height_mm: 188)
    Design::PaperSizeSeeder.call(other)   # model-built size has no docs; seed so we can assert the cascade
    dd_ids = other.document_designs.pluck(:id)
    assert dd_ids.any?
    assert_difference -> { @theme.paper_sizes.count }, -1 do
      delete design.theme_paper_size_path(@theme, other)
    end
    assert_response :redirect
    assert_equal 0, Design::DocumentDesign.where(id: dd_ids).count, "dependent: :destroy should cascade"
  end

  test "show links to add a new paper size and edit the active one" do
    get design.theme_path(@theme, paper_size_id: @ps.id)
    assert_response :success
    assert_select "a[href=?]", design.new_theme_paper_size_path(@theme)
    assert_select "a[href=?]", design.edit_theme_paper_size_path(@theme, @ps)
  end

  test "regenerate re-derives non-overridden defaults but preserves an overridden field" do
    # Override body_line_count via update; regenerate must keep it.
    patch design.theme_paper_size_path(@theme, @ps), params: { paper_size: { body_line_count: 99 } }
    # Clear a non-overridden margin to a sentinel so we can see it recomputed.
    @ps.update_columns(left_margin_mm: 1)
    post design.regenerate_theme_paper_size_path(@theme, @ps)
    assert_response :redirect
    @ps.reload
    assert_equal 99, @ps.body_line_count, "overridden field must survive regenerate"
    assert_not_equal 1.0, @ps.left_margin_mm, "non-overridden margin should be recomputed"
  end
end
