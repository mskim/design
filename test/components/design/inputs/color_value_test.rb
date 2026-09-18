require "test_helper"

class Design::ColorValueTest < ActiveSupport::TestCase
  CV = Design::Views::Inputs::ColorValue

  test "summary mirrors color_math.js summaryText" do
    assert_equal "C0 M0 Y0 K100", CV.summary("CMYK=0,0,0,100")
    assert_equal "C0 M10 Y0 K43", CV.summary("CMYK=0.0,10.0,0,43")
    assert_equal "#3b82f6", CV.summary("#3B82F6")
    assert_equal "white", CV.summary("white")
    assert_equal "", CV.summary(nil)
  end

  test "format and swatch" do
    assert_equal :cmyk, CV.format("CMYK=0,0,0,0")
    assert_equal :hex, CV.format("#abcdef")
    assert_equal :named, CV.format("black")
    assert_nil CV.format("")
    assert_equal "#000000", CV.swatch_hex("CMYK=0,0,0,100")
    assert_equal "#ffffff", CV.swatch_hex("white")
    assert_nil CV.swatch_hex("")
    assert_includes CV.swatch_style(""), "repeating-conic-gradient"
    assert_equal "background: #000000", CV.swatch_style("CMYK=0,0,0,100")
  end
end
