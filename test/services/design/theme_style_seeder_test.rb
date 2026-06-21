require "test_helper"

class Design::ThemeStyleSeederTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.new(name: "Seeder #{SecureRandom.hex(3)}", locale: "ko")
    @theme.save!(validate: false) # bypass any callbacks until Task 14
    @theme.table_styles.destroy_all
    @theme.base_paragraph_styles.where(name: %w[table_heading_cell table_body_cell]).destroy_all
  end

  test "creates 5 table_styles + 2 cell paragraph_styles for fresh theme" do
    Design::ThemeStyleSeeder.call(@theme)
    assert_equal 5, @theme.table_styles.count
    assert_equal %w[grid minimal simple striped zebra].sort,
                 @theme.table_styles.pluck(:name).sort
    assert @theme.base_paragraph_styles.exists?(name: "table_heading_cell")
    assert @theme.base_paragraph_styles.exists?(name: "table_body_cell")
  end

  test "is idempotent" do
    Design::ThemeStyleSeeder.call(@theme)
    Design::ThemeStyleSeeder.call(@theme)
    assert_equal 5, @theme.table_styles.count
    assert_equal 1, @theme.base_paragraph_styles.where(name: "table_heading_cell").count
  end

  test "fills in only missing rows" do
    @theme.table_styles.create!(
      name: "zebra", border_width: 99.0, border_color: "#000000",
      border_style: "full", cell_padding: 4, outer_border_width: 0.5,
      header_font_weight: "bold"
    )
    Design::ThemeStyleSeeder.call(@theme)
    assert_equal 5, @theme.table_styles.count
    assert_equal 99.0, @theme.table_styles.find_by(name: "zebra").border_width.to_f
  end

  test "reset(theme, name) restores defaults for a single style" do
    Design::ThemeStyleSeeder.call(@theme)
    zebra = @theme.table_styles.find_by(name: "zebra")
    zebra.update!(border_width: 99.0)
    Design::ThemeStyleSeeder.reset(@theme, "zebra")
    assert_equal 0.5, @theme.table_styles.find_by(name: "zebra").border_width.to_f
  end
end
