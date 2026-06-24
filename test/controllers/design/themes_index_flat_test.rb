require "test_helper"

class Design::ThemesIndexFlatTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david # admin (can_design?)
  end

  test "themes index links to the style browser" do
    get design.themes_path
    assert_response :success
    assert_select "a[href=?]", design.style_browser_path
  end

  test "index is a single flat grid with a New theme link and rich cards" do
    t = Design::Theme.create!(name: "FlatT #{SecureRandom.hex(3)}", locale: "ko")
    get design.themes_path
    assert_response :success
    assert_select "a[href=?]", design.new_theme_path        # gem-native New theme
    assert_includes response.body, t.name
    assert_includes response.body, t.locale.upcase          # locale badge
    assert_select ".themes-grid", 1                          # ONE grid (no system/custom split)
  end
end
