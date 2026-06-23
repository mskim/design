require "test_helper"

class Design::DefaultGeneratorTest < ActiveSupport::TestCase
  setup { @theme = Design::Theme.create!(name: "G #{SecureRandom.hex(3)}", locale: "ko") }

  test "creating a paper size fills computed margins + body_line_count" do
    ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    ps.reload
    assert_equal 22.0, ps.left_margin_mm.to_f
    assert_equal 18.0, ps.top_margin_mm.to_f
    assert_equal 28.0, ps.bottom_margin_mm.to_f
    assert_equal 3.0,  ps.binding_margin_mm.to_f
    assert_equal 23,   ps.body_line_count
  end

  test "A4 gets the two-anchor body_line_count (40) and proportional margins" do
    ps = @theme.paper_sizes.create!(size_name: "A4", width_mm: 210, height_mm: 297)
    ps.reload
    assert_equal 30.4, ps.left_margin_mm.to_f
    assert_equal 40,   ps.body_line_count
  end

  test "explicitly set margin is preserved (not clobbered)" do
    ps = @theme.paper_sizes.create!(size_name: "X", width_mm: 152, height_mm: 225, top_margin_mm: 99)
    assert_equal 99.0, ps.reload.top_margin_mm.to_f
    assert_equal 22.0, ps.left_margin_mm.to_f
  end

  test "regenerate is idempotent and honors overridden_fields" do
    ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    ps.update!(left_margin_mm: 12); ps.mark_overridden(:left_margin_mm)
    Design::DefaultGenerator.call(ps); ps.reload
    assert_equal 12.0, ps.left_margin_mm.to_f
    assert_equal 18.0, ps.top_margin_mm.to_f
  end
end
