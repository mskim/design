require "test_helper"

class Design::ThemesIndexPhlexTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david   # admin (can_design?)
    Design::Theme.create!(name: "Seoul", locale: "ko") unless Design::Theme.system_themes.exists?
  end

  test "themes index renders the Phlex page in the design layout" do
    get "/design/themes"
    assert_response :success
    assert_select "body.design-studio"
    assert_select ".themes-grid [data-theme-card]"   # two-column theme card gallery
    assert_match %r{/assets/design-\w+\.css}, response.body  # engine stylesheet loaded (digested)
  end

  test "design studio still gated to designer+" do
    sign_in :kevin                      # writer
    get "/design/themes"; assert_response :forbidden
    users(:kevin).update!(role: :designer); sign_in :kevin
    get "/design/themes"; assert_response :success
  end

  test "theme show renders in the design layout" do
    sign_in :david
    theme = Design::Theme.system_themes.first || Design::Theme.create!(name: "Seoul", locale: "ko")
    get "/design/themes/#{theme.id}"
    assert_response :success
    assert_select "body.design-studio"           # the isolated design layout (Phlex)
    assert_select "h1", text: theme.name
  end
end
