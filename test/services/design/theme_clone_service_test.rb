# engines/design/test/services/design/theme_clone_service_test.rb
require "test_helper"

class Design::ThemeCloneServiceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "u-#{SecureRandom.hex(3)}@example.com",
                         password: "password123", name: "U")
    @source = Design::Theme.create!(name: "Src #{SecureRandom.hex(3)}", locale: "ko",
                                    base_body_font: "smShinShinMyungjoP-30",
                                    base_body_font_size: 9.5,
                                    base_heading_font: "NotoSerifKR-Bold")
  end

  test "clones all 5 table_styles" do
    @source.table_styles.find_by(name: "zebra").update!(border_width: 99.0)

    cloned = Design::ThemeCloneService.new(@source, user: @user).clone

    assert_equal 5, cloned.table_styles.count
    assert_equal 99.0, cloned.table_styles.find_by(name: "zebra").border_width.to_f
  end

  test "clones table cell paragraph styles" do
    cloned = Design::ThemeCloneService.new(@source, user: @user).clone

    assert cloned.base_paragraph_styles.exists?(name: "table_heading_cell")
    assert cloned.base_paragraph_styles.exists?(name: "table_body_cell")
  end

  test "uses the provided name when one is given" do
    cloned = Design::ThemeCloneService.new(@source, user: @user, name: "My Custom Theme").clone

    assert_equal "My Custom Theme", cloned.name
  end

  test "falls back to the auto-generated name when the given name is blank" do
    cloned = Design::ThemeCloneService.new(@source, user: @user, name: "   ").clone

    assert_equal "#{@source.name} (Custom)", cloned.name
  end

  test "disambiguates a duplicate provided name" do
    Design::Theme.create!(name: "Dup", locale: "ko", user: @user)

    cloned = Design::ThemeCloneService.new(@source, user: @user, name: "Dup").clone

    assert_equal "Dup 2", cloned.name
  end
end
