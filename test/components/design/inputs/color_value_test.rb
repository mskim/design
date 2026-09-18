require "test_helper"
require "json"
require "open3"

class Design::ColorValueTest < ActiveSupport::TestCase
  CV = Design::Views::Inputs::ColorValue

  test "summary mirrors color_math.js summaryText" do
    assert_equal "C0 M0 Y0 K100", CV.summary("CMYK=0,0,0,100")
    assert_equal "C0 M10 Y0 K43", CV.summary("CMYK=0.0,10.0,0,43")
    assert_equal "#3b82f6", CV.summary("#3B82F6")
    assert_equal "white", CV.summary("white")
    assert_equal "", CV.summary(nil)
  end

  test "CMYK with empty parts is not a colour" do
    assert_nil CV.format("CMYK=,,,")
    assert_equal "CMYK=,,,", CV.summary("CMYK=,,,")
    assert_equal "CMYK=1,2,3,", CV.summary("CMYK=1,2,3,")
  end

  PARITY_INPUTS = [ "CMYK=0,0,0,100", "CMYK=0.15,0.35,1.15,5.55", "CMYK=,,,", "CMYK=1,2,3,",
                    "#3B82F6", "white", "" ].freeze

  test "summary is identical to color_math.js summaryText (node)" do
    node = `command -v node`.strip
    skip "node is not installed" if node.empty?
    script = <<~JS
      const { pathToFileURL } = require("node:url")
      const [file, json] = process.argv.slice(-2)
      import(pathToFileURL(file).href).then((m) => console.log(JSON.stringify(JSON.parse(json).map(m.summaryText))))
    JS
    file = Design::Engine.root.join("app/javascript/design-controllers/design/color_math.js").to_s
    out, err, status = Open3.capture3(node, "-e", script, file, PARITY_INPUTS.to_json)
    assert status.success?, err
    assert_equal PARITY_INPUTS.map { |s| CV.summary(s) }, JSON.parse(out)
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
