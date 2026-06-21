require "test_helper"
require "sqlite3"

class Design::ThemeDbExportServiceTest < ActiveSupport::TestCase
  test "exported db has table_styles table populated" do
    theme = Design::Theme.create!(
      name: "Exp #{SecureRandom.hex(3)}", locale: "ko",
      base_body_font: "smShinShinMyungjoP-30",
      base_body_font_size: 9.5,
      base_heading_font: "NotoSerifKR-Bold"
    )
    path = Design::ThemeDbExportService.new(theme).export!

    db = SQLite3::Database.new(path)
    db.results_as_hash = true
    rows = db.execute("SELECT name FROM table_styles WHERE theme_id = ?", theme.id)
    assert_equal %w[grid minimal simple striped zebra].sort,
                 rows.map { _1["name"] }.sort
  ensure
    db&.close
    File.delete(path) if path && File.exist?(path)
  end

  test "exported paragraph_styles schema has vertical_align column" do
    theme = Design::Theme.create!(
      name: "Exp2 #{SecureRandom.hex(3)}", locale: "ko",
      base_body_font: "smShinShinMyungjoP-30",
      base_body_font_size: 9.5,
      base_heading_font: "NotoSerifKR-Bold"
    )
    path = Design::ThemeDbExportService.new(theme).export!

    db = SQLite3::Database.new(path)
    cols = db.execute("PRAGMA table_info(paragraph_styles)").map { |c| c[1] }
    assert_includes cols, "vertical_align"
  ensure
    db&.close
    File.delete(path) if path && File.exist?(path)
  end

  test "exported .db document_designs includes the superset columns" do
    theme = Design::Theme.create!(name: "Exp #{SecureRandom.hex(3)}", locale: "ko")
    ps = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    ps.document_designs.create!(doc_type: "chapter", cover_type: "spread", has_document_cover: true,
                                footnote_char: "*", page_type: "single_page", heading_bg_gradient_start: "#fff")
    path = Design::ThemeDbExportService.new(theme).export!
    db = SQLite3::Database.new(path); db.results_as_hash = true
    row = db.execute("SELECT * FROM document_designs WHERE doc_type = 'chapter'").first
    db.close
    assert_equal "spread", row["cover_type"]
    assert_equal "*", row["footnote_char"]
    assert_equal "single_page", row["page_type"]
    assert_equal "#fff", row["heading_bg_gradient_start"]
  ensure
    File.delete(path) if path && File.exist?(path)
  end
end
