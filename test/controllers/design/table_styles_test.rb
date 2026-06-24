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

  test "preview renders a jpeg natively when no hook is registered" do
    assert_nil Design.config.table_style_preview
    get design.preview_theme_table_style_path(@theme, @ts)
    assert_response :success
    assert_equal "image/jpeg", response.media_type
    assert response.body.bytesize > 1000, "native jpeg too small"
  end

  test "a render error degrades to 422, not 500" do
    Design.config.table_style_preview = ->(_t, _ts) { raise "boom" }  # restored by teardown
    get design.preview_theme_table_style_path(@theme, @ts)
    assert_response :unprocessable_entity
  end

  test "unknown table style is 404" do
    get design.preview_theme_table_style_path(@theme, 0)
    assert_response :not_found
  end

  test "edit renders the two-pane editor with the three sections + reset" do
    get design.edit_theme_table_style_path(@theme, @ts)
    assert_response :success
    assert_select "body.design-studio"
    assert_select "input[name=?]", "table_style[border_width]"
    assert_select "select[name=?]", "table_style[border_style]"
    assert_select "input[name=?]", "table_style[header_background]"
    assert_select "form[action=?]", design.reset_theme_table_style_path(@theme, @ts)
  end

  test "edit shows a no-preview placeholder when no hook is registered" do
    get design.edit_theme_table_style_path(@theme, @ts)
    assert_select "turbo-frame#preview_frame", count: 0   # placeholder renders no preview frame
    assert_includes response.body, I18n.t("design.table_styles.no_preview")
  end

  test "edit shows the preview img when the hook is registered" do
    Design.config.table_style_preview = ->(t, ts) { "JPG" }
    get design.edit_theme_table_style_path(@theme, @ts)
    assert_select "turbo-frame#preview_frame img[src*=?]", "preview"
  ensure
    Design.config.table_style_preview = nil
  end

  test "update round-trips fields and redirects to edit" do
    patch design.theme_table_style_path(@theme, @ts),
          params: { table_style: { border_width: 3.5, header_font_weight: "bold", header_background: "#222222" } }
    assert_redirected_to design.edit_theme_table_style_path(@theme, @ts)
    @ts.reload
    assert_equal 3.5, @ts.border_width
    assert_equal "bold", @ts.header_font_weight
    assert_equal "#222222", @ts.header_background
  end

  test "update with invalid params re-renders 422" do
    patch design.theme_table_style_path(@theme, @ts), params: { table_style: { border_style: "bogus" } }
    assert_response :unprocessable_entity
  end

  test "reset restores the seeded defaults" do
    original = @ts.border_width
    @ts.update_columns(border_width: 99)
    post design.reset_theme_table_style_path(@theme, @ts)
    assert_redirected_to design.edit_theme_table_style_path(@theme, @ts)
    assert_equal original, @ts.reload.border_width
  end

  test "show redirects to edit" do
    get design.theme_table_style_path(@theme, @ts)
    assert_redirected_to design.edit_theme_table_style_path(@theme, @ts)
  end

  test "a non-editable (system) theme is forbidden" do
    sys = Design::Theme.create!(name: "Sys #{SecureRandom.hex(3)}", locale: "ko", user_id: nil)
    sys_ts = sys.table_styles.find_by(name: "grid")
    get design.edit_theme_table_style_path(sys, sys_ts)
    assert_response :forbidden
  end
end
