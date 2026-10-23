require "test_helper"
require "sqlite3"

# book_write C3f2: the back flap's promoted-book layout (image width as a % of the flap's text
# width, its height ÷ width, the gap under each book) reaches the .db, today's values by default; a
# host app without the columns still exports (NULLs, which designcraft_rb reads as those defaults).
class Design::ThemeDbExportBackWingTest < ActiveSupport::TestCase
  COLUMNS = %w[back_wing_image_width_percent back_wing_image_ratio back_wing_item_gap].freeze

  setup do
    @theme = Design::Theme.create!(name: "BW #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @wing = @ps.document_designs.create!(doc_type: "back_wing", back_wing_image_width_percent: 30,
                                         back_wing_image_ratio: 1.55, back_wing_item_gap: 4.5)
    @ps.document_designs.create!(doc_type: "front_page")
  end

  test "export writes the three columns; a row left alone has today's defaults" do
    path = Design::ThemeDbExportService.new(@theme).export!
    db = SQLite3::Database.new(path)
    db.results_as_hash = true
    rows = db.execute("SELECT doc_type, #{COLUMNS.join(', ')} FROM document_designs").to_h { [ it["doc_type"], it.values_at(*COLUMNS) ] }
    assert_equal({ "back_wing" => [ 30, 1.55, 4.5 ], "front_page" => [ 20, 1.4, 10.0 ] }, rows)
  ensure
    db&.close
    File.delete(path) if path && File.exist?(path)
  end

  test "a record loaded without the columns exports NULLs" do
    partial = Design::DocumentDesign.select(Design::DocumentDesign.column_names - COLUMNS).find(@wing.id)
    values = Design::ThemeDbExportService.new(@theme).send(:document_design_values, partial)

    assert_equal 54, values.size
    assert_equal [ nil, nil, nil ], values[-5, 3] # the three; then created_at, updated_at
  end
end
