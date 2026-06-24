require "test_helper"

class Design::HexToCmykTest < ActiveSupport::TestCase
  test "white is all zero" do
    assert_equal [ 0, 0, 0, 0 ], Design::HexToCmyk.call("#ffffff")
  end

  test "black is full key" do
    assert_equal [ 0, 0, 0, 100 ], Design::HexToCmyk.call("#000000")
  end

  test "grey is key only" do
    assert_equal [ 0, 0, 0, 20 ], Design::HexToCmyk.call("#cccccc")
  end

  test "nil and blank return nil" do
    assert_nil Design::HexToCmyk.call(nil)
    assert_nil Design::HexToCmyk.call("")
  end
end
