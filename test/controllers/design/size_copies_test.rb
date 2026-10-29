require "test_helper"

# "Copy for another size" (Design::SizeCopiesController): a design has one
# paper size, so another size is another design.
class Design::SizeCopiesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @theme = Design::Theme.create!(name: "클래식 #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "152mmx225mm", local_name: "신국판", width_mm: 152, height_mm: 225)
    @ps.document_designs.create!(doc_type: "chapter")
  end

  teardown do
    Design::Theme.where.not(id: @theme.id).where("name LIKE ?", "#{@theme.name}%").find_each do |t|
      File.delete(t.db_path) if File.exist?(t.db_path)
    end
  end

  def copy = Design::Theme.where.not(id: @theme.id).order(:id).last

  test "new offers the standard sizes, a custom size and a name" do
    get design.new_theme_size_copy_path(@theme)

    assert_response :success
    assert_select "form[action=?][method=post]", design.theme_size_copy_path(@theme) do
      Design::PaperSize::STANDARD_SIZES.each do |s|
        assert_select "select[name=?] option[value=?]", "size_copy[size]", s[:local_name]
      end
      assert_select "input[name=?]", "size_copy[width_mm]"
      assert_select "input[name=?]", "size_copy[height_mm]"
      assert_select "input[name=?]", "size_copy[name]"
    end
  end

  test "new is titled from design.size_copies.new_title, in Korean under :ko" do
    Design.config.locale_for = -> { :ko }
    get design.new_theme_size_copy_path(@theme)

    assert_includes response.body, "다른 판형으로 복사"
    assert_includes response.body, "사륙판 (128×188 mm)"
  end

  test "create with a standard size makes a one-size design and opens it" do
    assert_difference -> { Design::Theme.count }, 1 do
      post design.theme_size_copy_path(@theme), params: { size_copy: { size: "사륙판" } }
    end

    assert_redirected_to design.theme_path(copy)
    assert_equal "#{@theme.name} 사륙판", copy.name
    assert_equal [ [ "사륙판", 128, 188 ] ], copy.paper_sizes.map { |ps| [ ps.local_name, ps.width_mm.to_i, ps.height_mm.to_i ] }
    assert_equal 1, @theme.paper_sizes.count, "the source keeps its one size"
    follow_redirect!
    assert_includes response.body, copy.name
  end

  test "a custom width and height win over the selected size" do
    post design.theme_size_copy_path(@theme), params: { size_copy: { size: "A4", width_mm: "150", height_mm: "220" } }

    ps = copy.paper_sizes.sole
    assert_equal [ 150, 220 ], [ ps.width_mm.to_i, ps.height_mm.to_i ]
    assert_equal "#{@theme.name} 150x220", copy.name
  end

  test "a typed name names the copy" do
    post design.theme_size_copy_path(@theme), params: { size_copy: { size: "A4", name: "큰 클래식 #{@theme.id}" } }

    assert_equal "큰 클래식 #{@theme.id}", copy.name
  end

  test "create without a size re-renders the form" do
    assert_no_difference -> { Design::Theme.count } do
      post design.theme_size_copy_path(@theme), params: { size_copy: { size: "", width_mm: "150" } }
    end

    assert_response :unprocessable_entity
    assert_select "form[action=?]", design.theme_size_copy_path(@theme)
  end

  test "any designer who can see a read-only system design can copy it, as their own" do
    Design.config.authoring = false
    post design.theme_size_copy_path(@theme), params: { size_copy: { size: "A4" } }

    assert_equal users(:david), copy.user
  end

  test "a non-designer cannot copy" do
    sign_in :jz
    get design.new_theme_size_copy_path(@theme)
    assert_response :forbidden
  end

  test "a book's own design is not reachable" do
    book_design = Design::Theme.create!(name: "Book #{SecureRandom.hex(3)}", locale: "ko", book_id: 1)
    get design.new_theme_size_copy_path(book_design)
    assert_response :not_found
  end

  # The old entry points (the studio rail still links them) lead here.
  test "generate_sizes leads to the copy form" do
    post design.generate_sizes_theme_path(@theme)
    assert_redirected_to design.new_theme_size_copy_path(@theme)
  end

  test "a new paper size on a theme with a size leads to the copy form" do
    get design.new_theme_paper_size_path(@theme)
    assert_redirected_to design.new_theme_size_copy_path(@theme)

    assert_no_difference -> { Design::PaperSize.count } do
      post design.theme_paper_sizes_path(@theme), params: { paper_size: { size_name: "A4", width_mm: 210, height_mm: 297 } }
    end
    assert_redirected_to design.new_theme_size_copy_path(@theme)
  end

  test "a theme's only size is not deleted" do
    @theme.update!(user: users(:david))
    assert_no_difference -> { @theme.paper_sizes.count } do
      delete design.theme_paper_size_path(@theme, @ps)
    end
    assert_redirected_to design.edit_theme_paper_size_path(@theme, @ps)
    assert_equal I18n.t("design.paper_sizes.only_size"), flash[:alert]
  end
end
