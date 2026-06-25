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

  # Each theme renders as a card linking to its show page.
  test "renders each theme as a card linking to its show page" do
    assert_select ".theme-card", minimum: 2
    assert_select "a[href=?]", "/design/themes/#{@system.id}"
    assert_select "a[href=?]", "/design/themes/#{@mine.id}"
    assert_includes response.body, @system.name
    assert_includes response.body, @mine.name
  end

  # The card actions live inline on the index: Clone (always — the start-a-new-
  # design path) plus Rename/Delete for themes the user may edit (here @mine).
  test "renders inline clone, rename, and delete actions on the cards" do
    assert_select "form[action=?]", "/design/themes/#{@system.id}/clone"
    assert_select %(form[action="/design/themes/#{@mine.id}"] input[name="theme[name]"])
    assert_select %(form[action="/design/themes/#{@mine.id}"] input[name="_method"][value="delete"])
  end

  # The from-scratch New theme link is an authoring-host tool only.
  test "offers a New theme link on authoring hosts only" do
    Design.config.authoring = true
    get "/design/themes"
    assert_select "a[href=?]", design.new_theme_path

    Design.config.authoring = false
    get "/design/themes"
    assert_select "a[href=?]", design.new_theme_path, false
  end
end
