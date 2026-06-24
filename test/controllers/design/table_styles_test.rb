require "test_helper"

class Design::TableStylesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :david
    @theme = Design::Theme.create!(name: "TS #{SecureRandom.hex(3)}", locale: "ko", user_id: users(:david).id)
    @ts = @theme.table_styles.find_by(name: "grid") # auto-seeded on theme create
  end

  test "preview sends host-rendered jpeg when the hook is registered" do
    Design.config.table_style_preview = ->(theme, table_style) { "JPGDATA" }
    get design.preview_theme_table_style_path(@theme, @ts)
    assert_response :success
    assert_equal "image/jpeg", response.media_type
    assert_equal "JPGDATA", response.body
  ensure
    Design.config.table_style_preview = nil
  end

  test "preview is 404 when no hook is registered" do
    get design.preview_theme_table_style_path(@theme, @ts)
    assert_response :not_found
  end
end
