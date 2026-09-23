require "test_helper"

# D5: the old five border fields → the twelve. What the old chain set is
# pinned (0 / "none" for a flagged-off side or corner, so the normaliser can
# compare a child with its parent value for value); what it left unset stays
# nil (latent: inherits, as the old model would have).
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
    left_only = LB.convert({ "border_thickness" => 1, "border_side" => "1,0,0,0" }, order: :cover)
    assert_equal [ 0, 0, 0, 1.0 ], sides(left_only, "thickness"), "a cover's first flag is the LEFT side"
  end

  test "convert: blank or unreadable flags mean all four" do
    [ nil, "", "1,1", "a,b,c,d" ].each do |flags|
      assert_equal [ 2.0 ] * 4, sides(LB.convert({ "border_thickness" => 2, "border_side" => flags }), "thickness"), flags.inspect
    end
  end

  test "convert: an unset thickness with no sides leaves every side unset" do
    [ nil, "", "  " ].each do |t|
      out = LB.convert({ "border_thickness" => t })
      assert_equal [ nil ] * 4, sides(out, "thickness"), t.inspect
      assert_equal [ nil ] * 4, sides(out, "color"), t.inspect
    end
  end

  test "convert: an unset thickness pins only the flagged-off sides" do
    out = LB.convert({ "border_thickness" => nil, "border_side" => "1,0,1,0" })
    assert_equal [ nil, 0, nil, 0 ], sides(out, "thickness")
    assert_equal [ nil ] * 4, sides(out, "color")
  end

  test "convert: an unset thickness keeps a set colour latent on every side" do
    out = LB.convert({ "border_color" => "#00ff00", "border_side" => "0,1,1,1" })
    assert_equal [ 0, nil, nil, nil ], sides(out, "thickness")
    assert_equal [ "#00ff00" ] * 4, sides(out, "color")
  end

  test "convert: a 0, negative or unreadable thickness is no line on any side and no colour" do
    [ 0, "0", "-1", "abc" ].each do |t|
      out = LB.convert({ "border_thickness" => t, "border_color" => "#000000", "border_side" => "1,0,1,0" })
      assert_equal [ 0 ] * 4, sides(out, "thickness"), t.inspect
      assert_equal [ nil ] * 4, sides(out, "color"), t.inspect
    end
  end

  test "convert: corners — the preset on flagged corners, none elsewhere; large becomes full" do
    out = LB.convert({ "corner_radius" => "large", "rounded_corners" => "1,1,0,0" })
    assert_equal %w[full full none none], corners(out)
    assert_equal %w[medium] * 4, corners(LB.convert({ "corner_radius" => "medium" }))
  end

  test "convert: an explicit none or unreadable preset squares all four corners" do
    [ "none", "huge" ].each do |r|
      assert_equal %w[none] * 4, corners(LB.convert({ "corner_radius" => r, "rounded_corners" => "1,1,0,0" })), r.inspect
      assert_equal %w[none] * 4, corners(LB.convert({ "corner_radius" => r })), r.inspect
    end
  end

  test "convert: an unset preset pins only the flagged-off corners" do
    [ nil, "", " " ].each do |r|
      assert_equal [ nil ] * 4, corners(LB.convert({ "corner_radius" => r })), r.inspect
      assert_equal [ nil, nil, "none", "none" ], corners(LB.convert({ "corner_radius" => r, "rounded_corners" => "1,1,0,0" })), r.inspect
    end
  end

  test "convert returns exactly the twelve new field names, set or not" do
    assert_equal LB::NEW_FIELDS.sort, LB.convert({}).keys.sort
    assert LB.convert({}).values.all?(&:nil?), "an empty old style sets nothing"
  end

  test "a BigDecimal thickness from the database converts" do
    assert_equal [ 0.25 ] * 4, sides(LB.convert({ "border_thickness" => BigDecimal("0.25") }), "thickness")
  end
end
