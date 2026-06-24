require "test_helper"

class Design::ActionRegistryTest < ActiveSupport::TestCase
  setup { @reg = Design::ActionRegistry.new }

  test "for stores a block, resolve returns it" do
    blk = ->(theme) { [{ label: "X", path: "/x" }] }
    @reg.for(:theme_show, &blk)
    assert_equal blk, @reg.resolve(:theme_show)
  end

  test "resolve returns nil for an unregistered slot" do
    assert_nil @reg.resolve(:nope)
  end

  test "string and symbol slot names are interchangeable" do
    @reg.for("theme_show") { [] }
    assert_not_nil @reg.resolve(:theme_show)
  end

  test "Design.config.actions is a memoized ActionRegistry" do
    assert_instance_of Design::ActionRegistry, Design.config.actions
    assert_same Design.config.actions, Design.config.actions
  end
end
