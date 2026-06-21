require "test_helper"

class Design::ParagraphStylesFormTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @theme = Design::Theme.create!(name: "Owned #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "chapter")
  end

  test "theme-level paragraph style form renders + updates" do
    style = @theme.base_paragraph_styles.create!(name: "body")
    get design.edit_theme_theme_paragraph_style_path(@theme, style)
    assert_response :success
    assert_select "body.design-studio"
    assert_select "[data-controller='design--color-mode-field']"
    patch design.theme_theme_paragraph_style_path(@theme, style), params: { paragraph_style: { font_size: 12 } }
    assert_response :redirect
    assert_equal 12.0, style.reload.font_size
  end

  test "base (paper-size) level form renders + updates" do
    style = @ps.paragraph_styles.create!(name: "h2")
    get design.edit_theme_paper_size_base_paragraph_style_path(@theme, @ps, style)
    assert_response :success
    assert_select "[data-controller='design--color-mode-field']"
    patch design.theme_paper_size_base_paragraph_style_path(@theme, @ps, style), params: { paragraph_style: { font_size: 14 } }
    assert_equal 14.0, style.reload.font_size
  end

  test "document level form renders + updates" do
    style = @dd.paragraph_styles.create!(name: "caption")
    get design.edit_theme_paper_size_document_design_paragraph_style_path(@theme, @ps, @dd, style)
    assert_response :success
    patch design.theme_paper_size_document_design_paragraph_style_path(@theme, @ps, @dd, style), params: { paragraph_style: { font_size: 9 } }
    assert_equal 9.0, style.reload.font_size
  end
end
