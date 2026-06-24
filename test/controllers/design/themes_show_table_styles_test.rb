require "test_helper"

class Design::ThemesShowTableStylesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @theme = Design::Theme.create!(name: "TSG #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ts = @theme.table_styles.find_by(name: "grid")
  end

  test "theme show lists table styles linking to their editors" do
    get design.theme_path(@theme)
    assert_response :success
    assert_includes response.body, I18n.t("design.table_styles.section_title")
    assert_select "a[href=?]", design.edit_theme_table_style_path(@theme, @ts)
  end

  test "theme show renders table-style preview images with no hook registered" do
    assert_nil Design.config.table_style_preview
    get design.theme_path(@theme)
    assert_response :success
    assert_select "img[src*=?]", "table_styles/#{@ts.id}/preview"
    assert_not_includes response.body, "No preview"
  end
end
