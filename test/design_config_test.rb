require "test_helper"

class DesignConfigTest < ActiveSupport::TestCase
  # Restore config after each test so other tests aren't affected
  setup do
    @saved_config = Design.config.dup
  end

  teardown do
    Design.instance_variable_set(:@config, @saved_config)
  end

  test "Configuration authoring defaults to false" do
    assert_not Design::Configuration.new.authoring
  end

  test "authoring? returns true when configured true" do
    Design.configure { |c| c.authoring = true }
    assert Design.authoring?
  end

  test "authoring? returns false when configured false" do
    Design.configure { |c| c.authoring = false }
    assert_not Design.authoring?
  end

  test "current_user calls the configured lambda" do
    fake_user = Object.new
    Design.configure { |c| c.current_user = -> { fake_user } }
    assert_equal fake_user, Design.current_user
  end

  test "Configuration current_user defaults to nil" do
    assert_nil Design::Configuration.new.current_user
  end

  test "authorize calls the configured lambda with the user" do
    authorized_user = Object.new
    Design.configure { |c| c.authorize = ->(user) { user == authorized_user } }
    assert Design.authorize(authorized_user)
    assert_not Design.authorize(Object.new)
  end

  test "Configuration authorize defaults to nil (falsey, safe default)" do
    assert_nil Design::Configuration.new.authorize
  end

  test "user_class defaults to 'User'" do
    assert_equal "User", Design.config.user_class
  end

  test "configure yields a Configuration object" do
    yielded = nil
    Design.configure { |c| yielded = c }
    assert_instance_of Design::Configuration, yielded
  end

  test "configure is additive across multiple calls" do
    Design.configure { |c| c.authoring = true }
    Design.configure { |c| c.user_class = "Admin" }
    assert Design.authoring?
    assert_equal "Admin", Design.config.user_class
  end

  test "themes_dir back-compat: Design.themes_dir readable/writable" do
    original = Design.themes_dir
    Design.themes_dir = "/tmp/fake_themes"
    assert_equal "/tmp/fake_themes", Design.themes_dir
  ensure
    Design.themes_dir = original
  end
end
