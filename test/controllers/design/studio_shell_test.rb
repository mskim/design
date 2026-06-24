require "test_helper"

class Design::StudioShellTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david # admin (can_design?)
    @theme = Design::Theme.create!(name: "S #{SecureRandom.hex(3)}", locale: "ko")
  end

  test "themes index renders inside the shell with its real body content" do
    get design.themes_path
    assert_response :success
    assert_select "header", 1                                   # the shell's single top bar
    assert_select "main"                                        # shell main region
    assert_select "main .themes-grid"                           # the index's REAL body content renders inside main
    assert_select "a.design-studio__home"                      # shell home link
    assert_not_includes response.body, "design-studio__header"  # old per-view header removed
  end
end
