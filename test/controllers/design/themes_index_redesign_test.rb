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

  test "lays system and custom themes out in two columns" do
    assert_select ".themes-grid section[data-themes=system]"
    assert_select ".themes-grid section[data-themes=custom]"
  end

  test "renders each theme as a card with a chapter preview and book-list-style meta" do
    assert_select "section[data-themes=system] [data-theme-card]" do
      assert_select ".theme-card__preview"
      assert_select ".theme-card__name", text: @system.name
      assert_select ".theme-card__meta" # paper sizes / doc types summary
    end
  end

  test "system themes can be cloned with a chosen name" do
    assert_select "form[action=?][method=post]", "/design/themes/#{@system.id}/clone" do
      assert_select "input[name=name]"
    end
  end

  test "custom themes can be renamed inline" do
    assert_select "section[data-themes=custom] form[action=?]", "/design/themes/#{@mine.id}" do
      assert_select "input[name=?]", "theme[name]"
    end
  end
end
