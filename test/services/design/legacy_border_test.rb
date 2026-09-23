require "test_helper"

# D5: the old five border fields → the twelve. Every converted field is set
# (0 / "none" rather than nil), so the normaliser can compare a child with
# its parent value for value.
class Design::LegacyBorderTest < ActiveSupport::TestCase
  LB = Design::LegacyBorder

  def sides(out, suffix) = %w[top right bottom left].map { |s| out["border_#{s}_#{suffix}"] }
  def corners(out) = %w[top_left top_right bottom_right bottom_left].map { |c| out["corner_#{c}"] }

  test "overlay: nil and blank fall back to the layer below, per field" do
    base = { "border_thickness" => 1, "border_color" => "CMYK=0,0,0,100", "corner_radius" => "small" }
    chapter = { "border_thickness" => nil, "border_color" => " ", "border_side" => "1,0,1,0" }
    own = { "corner_radius" => "large" }
    assert_equal({ "border_thickness" => 1, "border_color" => "CMYK=0,0,0,100", "border_side" => "1,0,1,0",
                   "rounded_corners" => nil, "corner_radius" => "large" }, LB.overlay([ base, chapter, own ]))
    assert_equal LB::OLD_FIELDS.index_with { nil }, LB.overlay([ nil, nil ])
  end

  test "convert: on sides get the thickness, off sides 0, every side the colour" do
    out = LB.convert({ "border_thickness" => "1.5", "border_color" => "#ff0000", "border_side" => "1,0,1,0" })
    assert_equal [ 1.5, 0, 1.5, 0 ], sides(out, "thickness"), "studio order: top, right, bottom, left"
    assert_equal [ "#ff0000" ] * 4, sides(out, "color")
  end

  test "convert: the cover order reads the same flags as left, top, right, bottom" do
    out = LB.convert({ "border_thickness" => 1, "border_side" => "0,1,0,1" }, order: :cover)
    assert_equal [ 1.0, 0, 1.0, 0 ], sides(out, "thickness"), "a cover's 0,1,0,1 is top and bottom"
  end

  test "convert: blank or unreadable flags mean all four" do
    [ nil, "", "1,1", "a,b,c,d" ].each do |flags|
      assert_equal [ 2.0 ] * 4, sides(LB.convert({ "border_thickness" => 2, "border_side" => flags }), "thickness"), flags.inspect
    end
  end

  test "convert: no thickness is no line on any side and no colour" do
    [ nil, "", 0, "-1", "abc" ].each do |t|
      out = LB.convert({ "border_thickness" => t, "border_color" => "#000000" })
      assert_equal [ 0 ] * 4, sides(out, "thickness"), t.inspect
      assert_equal [ nil ] * 4, sides(out, "color"), t.inspect
    end
  end

  test "convert: corners — the preset on flagged corners, none elsewhere; large becomes full" do
    out = LB.convert({ "corner_radius" => "large", "rounded_corners" => "1,1,0,0" })
    assert_equal %w[full full none none], corners(out)
    assert_equal %w[medium] * 4, corners(LB.convert({ "corner_radius" => "medium" }))
    [ nil, "", "none", "huge" ].each { |r| assert_equal %w[none] * 4, corners(LB.convert({ "corner_radius" => r })), r.inspect }
  end

  test "convert returns exactly the twelve new field names" do
    assert_equal LB::NEW_FIELDS.sort, LB.convert({}).keys.sort
  end

  test "a BigDecimal thickness from the database converts" do
    assert_equal [ 0.25 ] * 4, sides(LB.convert({ "border_thickness" => BigDecimal("0.25") }), "thickness")
  end
end
