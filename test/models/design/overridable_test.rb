require "test_helper"

class Design::OverridableTest < ActiveSupport::TestCase
  setup { @theme = Design::Theme.create!(name: "O #{SecureRandom.hex(3)}", locale: "ko") }

  test "new paper size defaults to empty overridden_fields" do
    ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    assert_equal [], ps.reload.overridden_fields
  end

  test "explicitly provided generatable attrs are captured as overridden on create" do
    ps = @theme.paper_sizes.create!(size_name: "X", width_mm: 152, height_mm: 225, top_margin_mm: 99)
    assert ps.overridden?(:top_margin_mm)
    refute ps.overridden?(:left_margin_mm)
  end

  test "mark_overridden persists" do
    ps = @theme.paper_sizes.create!(size_name: "Y", width_mm: 152, height_mm: 225)
    ps.mark_overridden(:left_margin_mm)
    assert ps.reload.overridden?(:left_margin_mm)
  end

  test "mark_overridden_from_changes marks only changed generatable attrs" do
    ps = @theme.paper_sizes.create!(size_name: "Z", width_mm: 152, height_mm: 225)
    ps.update!(left_margin_mm: 12)
    ps.mark_overridden_from_changes(%w[left_margin_mm top_margin_mm])
    assert ps.reload.overridden?(:left_margin_mm)
    refute ps.overridden?(:top_margin_mm)
  end
end
