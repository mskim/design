require "test_helper"
require "sqlite3"

# C3d2: a document design's start_on_right (open on a right-hand page) reaches the .db.
class Design::ThemeDbExportStartOnRightTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "SOR #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @ps.document_designs.create!(doc_type: "part_cover", start_on_right: true)
    @ps.document_designs.create!(doc_type: "chapter")
  end

  test "a document design starts with start_on_right false" do
    assert_equal false, Design::DocumentDesign.new.start_on_right
  end

  test "export writes start_on_right into document_designs" do
    path = Design::ThemeDbExportService.new(@theme).export!
    db = SQLite3::Database.new(path)
    db.results_as_hash = true
    flags = db.execute("SELECT doc_type, start_on_right FROM document_designs").to_h { [ it["doc_type"], it["start_on_right"] ] }
    assert_equal 1, flags["part_cover"]
    assert_equal 0, flags["chapter"]
  ensure
    db&.close
    File.delete(path) if path && File.exist?(path)
  end
end
