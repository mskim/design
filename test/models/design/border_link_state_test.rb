require "test_helper"

class Design::BorderLinkStateTest < ActiveSupport::TestCase
  PS = Design::ParagraphStyle
  State = Design::BorderLinkState

  def parent(**over) = PS::BORDER_FIELDS.index_with { nil }
                         .merge(PS::BORDER_THICKNESS_FIELDS.index_with { BigDecimal("1") })
                         .merge(PS::BORDER_COLOR_FIELDS.index_with { "CMYK=0,0,0,100" })
                         .merge(PS::CORNER_FIELDS.index_with { "none" }).merge(over.transform_keys(&:to_s))

  def own(**values) = PS.new(name: "x", **values)

  test "effective: the own value, else the parent's" do
    s = State.new(own: own(border_top_thickness: 2), parent: parent)
    assert_equal 2, s.effective("border_top_thickness")
    assert_equal 1, s.effective("border_left_thickness")
    assert_equal 1, State.new(own: nil, parent: parent).effective("border_top_thickness")
  end

  test "a box is linked when its groups' four effective values match" do
    assert State.new(own: nil, parent: parent).linked?("border")
    refute State.new(own: own(border_top_thickness: 2), parent: parent).linked?("border")
    refute State.new(own: own(border_left_color: "#ff0000"), parent: parent).linked?("border"), "colour counts too"
    assert State.new(own: own(border_left_color: "#ff0000"), parent: parent).linked?("corners")
    refute State.new(own: own(corner_top_left: "full"), parent: parent).linked?("corners")
    assert State.new(own: own(border_top_thickness: "1.0"), parent: parent).linked?("border"), "1.0 = 1"
  end

  test "common_own: the shared own value only when all four store it" do
    four = PS::CORNER_FIELDS.index_with { "full" }
    assert_equal "full", State.new(own: own(**four.transform_keys(&:to_sym)), parent: parent).common_own("corners")
    assert_nil State.new(own: own(corner_top_left: "full"), parent: parent).common_own("corners")
    assert_nil State.new(own: nil, parent: parent).common_own("corners")
  end

  test "common_effective: the shared effective value, or MIXED" do
    assert_equal "none", State.new(own: nil, parent: parent).common_effective("corners")
    assert_equal State::MIXED, State.new(own: own(corner_top_left: "full"), parent: parent).common_effective("corners")
  end

  test "group_state: changed beats generated beats inherited" do
    s = State.new(own: nil, parent: parent)
    states = PS::BORDER_FIELDS.index_with { :inherited }
    assert_equal :inherited, s.group_state("corners", states)
    assert_equal :generated, s.group_state("corners", states.merge("corner_top_left" => :generated))
    assert_equal :changed, s.group_state("corners", states.merge("corner_top_left" => :generated,
                                                                 "corner_bottom_left" => :changed))
  end
end
