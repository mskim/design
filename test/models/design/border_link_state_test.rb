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

  test "colours compare by meaning: a missing colour is black, spacing and hex case don't matter" do
    black_sides = { border_top_color: nil, border_right_color: "CMYK=0,0,0,100" }
    assert State.new(own: nil, parent: parent(border_top_color: nil)).linked?("border"), "nil = black"
    assert State.new(own: own(border_right_color: "CMYK=0, 0, 0, 100"), parent: parent).linked?("border"), "spacing"
    assert State.new(own: own(border_right_color: "CMYK=0.0,0,0,100.0"), parent: parent).linked?("border"), "number form"
    hexes = PS::BORDER_COLOR_FIELDS.index_with { "#ff0000" }.merge("border_top_color" => "#FF0000")
    assert State.new(own: nil, parent: parent(**hexes)).linked?("border"), "hex case"
    refute State.new(own: own(border_top_color: "#000000"), parent: parent).linked?("border"),
           "black CMYK and #000000 are different colour spaces"
    refute State.new(own: own(border_top_color: "#000000"), parent: parent(**black_sides)).linked?("border")
    assert_nil State.new(own: own(border_top_color: "CMYK=0,0,0,100"), parent: parent).common_own("border_color"),
               "a nil own colour matches black but isn't stored"
  end

  test "thickness and corners keep same_value?" do
    assert State.new(own: own(border_top_thickness: "1.00"), parent: parent).linked?("border")
    refute State.new(own: nil, parent: parent(border_top_thickness: nil)).linked?("border"), "no thickness is not 1"
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

  test "common_effective shows the colour that is set when a nil side means the same black" do
    s = State.new(own: nil, parent: parent(border_top_color: nil))
    assert_equal "CMYK=0,0,0,100", s.common_effective("border_color")
  end
end
