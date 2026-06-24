require "test_helper"

class Design::ThemesIndexRedesignTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david # admin (can_design?)
    @system = Design::Theme.system_themes.first || Design::Theme.create!(name: "Seoul", locale: "ko")
    @mine = Design::Theme.create!(name: "My Theme", locale: "ko", user: users(:david))
    get "/design/themes"
    assert_response :success
  end

  test "links back to the main app home" do
    assert_select "a.design-studio__home[href=?]", "/"
  end

  # Redesign: the index is now a single flat responsive grid of rich cards —
  # no system/custom column split.
  test "lays all themes out in one flat grid" do
    assert_select ".themes-grid", 1
    assert_select "section[data-themes=system]", count: 0
    assert_select "section[data-themes=custom]", count: 0
  end

  # Each theme renders as a card linking to its show page (where clone/edit live).
  test "renders each theme as a card linking to its show page" do
    assert_select "a.theme-card[href=?]", "/design/themes/#{@system.id}"
    assert_select "a.theme-card[href=?]", "/design/themes/#{@mine.id}"
    assert_includes response.body, @system.name
    assert_includes response.body, @mine.name
  end

  # Clone/rename moved off the index onto the theme show page — the index no
  # longer carries inline clone or rename forms.
  test "no inline clone or rename forms on the index" do
    assert_select "form[action=?]", "/design/themes/#{@system.id}/clone", count: 0
    assert_select "form input[name=?]", "theme[name]", count: 0
  end

  # The gem-native New theme link is present.
  test "offers a New theme link" do
    assert_select "a[href=?]", design.new_theme_path
  end
end
