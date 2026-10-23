require "test_helper"
require "sqlite3"

# C3d3: the chapter design's chapter_number_format (장 번호) reaches the .db; a host app without it
# (or without C3d2's start_on_right) still exports.
class Design::ThemeDbExportChapterNumberTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "CN #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @chapter = @ps.document_designs.create!(doc_type: "chapter", chapter_number_format: "제 {n} 장")
    @ps.document_designs.create!(doc_type: "poem")
  end

  test "export writes chapter_number_format into document_designs" do
    path = Design::ThemeDbExportService.new(@theme).export!
    db = SQLite3::Database.new(path)
    db.results_as_hash = true
    formats = db.execute("SELECT doc_type, chapter_number_format FROM document_designs").to_h { [ it["doc_type"], it["chapter_number_format"] ] }
    assert_equal({ "chapter" => "제 {n} 장", "poem" => nil }, formats)
  ensure
    db&.close
    File.delete(path) if path && File.exist?(path)
  end

  test "a record loaded without start_on_right or chapter_number_format exports their defaults" do
    partial = Design::DocumentDesign.select(Design::DocumentDesign.column_names - %w[start_on_right chapter_number_format]).find(@chapter.id)
    values = Design::ThemeDbExportService.new(@theme).send(:document_design_values, partial)

    assert_equal 51, values.size
    assert_equal [ 0, nil ], values[-4, 2] # start_on_right, chapter_number_format; then created_at, updated_at
  end
end
