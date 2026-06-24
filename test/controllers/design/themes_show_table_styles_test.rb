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
end
