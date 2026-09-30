require "test_helper"

class Design::Views::BookTreeParseTest < ActiveSupport::TestCase
  BT = Design::Views::BookTree

  test "no cookie means only bodymatter" do
    assert_equal %w[bodymatter], BT.open_keys(nil)
  end

  test "known keys are kept, unknown ones dropped" do
    assert_equal %w[frontmatter bodymatter], BT.open_keys("frontmatter,bodymatter")
    assert_equal %w[rearmatter], BT.open_keys("rearmatter,nope")
  end

  test "an all-junk cookie falls back to the default" do
    assert_equal %w[bodymatter], BT.open_keys("nope,<b>")
  end

  test "an empty cookie means every group closed" do
    assert_equal [], BT.open_keys("")
  end
end
