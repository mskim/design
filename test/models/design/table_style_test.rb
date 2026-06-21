require "test_helper"

class Design::TableStyleTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(
      name: "Test #{SecureRandom.hex(4)}", locale: "ko"
    )
    # Theme.after_create auto-seeds all 5 styles; clear them so individual
    # tests can build/create fresh styles without uniqueness collisions.
    @theme.table_styles.destroy_all
  end

  test "valid with all required fields" do
    ts = @theme.table_styles.build(
      name: "grid", border_width: 0.5, border_color: "#cccccc",
      border_style: "full", cell_padding: 4, outer_border_width: 0.5,
      header_font_weight: "bold"
    )
    assert ts.valid?, ts.errors.full_messages.inspect
  end

  test "name must be one of the 5 allowed" do
    %w[grid zebra striped minimal simple].each do |name|
      assert_includes Design::TableStyle::ALLOWED_NAMES, name
    end
  end

  test "rejects unknown name" do
    ts = @theme.table_styles.build(name: "rainbow")
    refute ts.valid?
    assert_includes ts.errors[:name], "is not included in the list"
  end

  test "border_style must be valid enum" do
    ts = @theme.table_styles.build(name: "grid", border_style: "diagonal")
    refute ts.valid?
  end

  test "header_font_weight must be normal or bold" do
    ts = @theme.table_styles.build(name: "grid", header_font_weight: "extra-bold")
    refute ts.valid?
  end

  test "name unique within theme" do
    @theme.table_styles.create!(name: "grid")
    dup = @theme.table_styles.build(name: "grid")
    refute dup.valid?
    assert_includes dup.errors[:name], "has already been taken"
  end
end
