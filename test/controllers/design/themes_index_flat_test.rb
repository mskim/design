require "test_helper"

class Design::ThemesIndexFlatTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david # admin (can_design?)
  end

  test "index is a single flat grid with rich cards; New theme is authoring-only" do
    t = Design::Theme.create!(name: "FlatT #{SecureRandom.hex(3)}", locale: "ko")

    Design.config.authoring = true
    get design.themes_path
    assert_response :success
    assert_select "a[href=?]", design.new_theme_path        # from-scratch New theme (authoring hosts only)
    assert_includes response.body, t.name
    assert_includes response.body, t.locale.upcase          # locale badge
    assert_select ".themes-grid", 1                          # ONE grid (no system/custom split)

    Design.config.authoring = false
    get design.themes_path
    assert_response :success
    assert_select "a[href=?]", design.new_theme_path, false  # hidden on consumer hosts
  end
end
