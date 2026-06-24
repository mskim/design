require "test_helper"

class Design::ThemesFormTest < ActionDispatch::IntegrationTest
  setup { sign_in :david }   # editability needs a signed-in designer

  test "new renders the form" do
    get design.new_theme_path
    assert_response :success
    assert_select "form"
    assert_includes response.body, %(name="theme[name]")
  end

  test "create with valid params makes a theme and redirects to show" do
    assert_difference -> { Design::Theme.count }, 1 do
      post design.themes_path, params: { theme: { name: "NewTheme #{SecureRandom.hex(3)}", locale: "ko" } }
    end
    assert_response :redirect
  end

  test "create with invalid params re-renders the form (422)" do
    post design.themes_path, params: { theme: { name: "", locale: "ko" } }
    assert_response :unprocessable_entity
    assert_select "form"
  end

  test "create assigns the current designer as owner (custom theme, creator can edit)" do
    post design.themes_path, params: { theme: { name: "Owned #{SecureRandom.hex(3)}", locale: "ko" } }
    theme = Design::Theme.order(:created_at).last
    refute theme.system?, "created theme should be owned (custom), not a system theme"
    assert_equal users(:david).id, theme.user_id
    get design.edit_theme_path(theme)   # creator can edit their own theme
    assert_response :success
  end

  test "edit + update round-trips fonts and locale (owned custom theme)" do
    theme = Design::Theme.create!(name: "E #{SecureRandom.hex(3)}", locale: "ko", user: users(:david))
    get design.edit_theme_path(theme)
    assert_response :success
    patch design.theme_path(theme), params: { theme: { base_body_font_size: 11.5, locale: "en" } }
    assert_equal 11.5, theme.reload.base_body_font_size.to_f
    assert_equal "en", theme.locale
  end
end
