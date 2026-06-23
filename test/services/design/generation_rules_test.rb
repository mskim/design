require "test_helper"

class Design::GenerationRulesTest < ActiveSupport::TestCase
  R = Design::GenerationRules

  test "margins reproduce both anchors" do
    assert_equal({ left: 22.0, top: 18.0, right: 22.0, bottom: 28.0, binding: 3.0 }, R.margins_for(152, 225))
    assert_equal({ left: 30.4, top: 23.8, right: 30.4, bottom: 37.0, binding: 4.1 }, R.margins_for(210, 297))
  end

  test "midpoint (국판 148x210) margins" do
    assert_equal({ left: 21.4, top: 16.8, right: 21.4, bottom: 26.1, binding: 2.9 }, R.margins_for(148, 210))
  end

  test "body_line_count two-anchor 23..40" do
    assert_equal 23, R.body_line_count_for(225)
    assert_equal 40, R.body_line_count_for(297)
    assert_equal 19, R.body_line_count_for(210)
  end

  test "heading scale + scaled_size hit anchors, floor applies" do
    assert_in_delta 0.75, R.heading_scale_for(225), 0.0001
    assert_in_delta 1.0,  R.heading_scale_for(297), 0.0001
    assert_equal 18.0, R.scaled_size(24, 225)
    assert_equal 24.0, R.scaled_size(24, 297)
    assert_equal 6.0,  R.scaled_size(7, 225)
  end

  test "out-of-range small size extrapolates with floors (사륙판 128x188)" do
    assert_equal({ left: 18.5, top: 15.0, right: 18.5, bottom: 23.4, binding: 2.5 }, R.margins_for(128, 188))
    assert_equal 14, R.body_line_count_for(188)
  end

  test "styles_for is real names; every relevance/scaled name is a known base style" do
    known = R::FAMILY_NAMES
    R::DOC_TYPE_STYLES.each_value { |list| assert_empty(list - known, "unknown names: #{(list - known).inspect}") }
    assert_empty(R::HEADING_SCALED_STYLES - known)
    assert_includes R.styles_for("poem"), "h2"
    assert_includes R.styles_for("chapter"), "footnote"
    assert_equal R.styles_for("chapter"), R.styles_for("nonexistent_type")
  end
end
