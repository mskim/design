require "test_helper"
require "sqlite3"

class Design::ThemeDbExportTocVAlignTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "EX #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @dd = @ps.document_designs.create!(doc_type: "toc", toc_v_align: "center")
  end

  test "export writes toc_v_align into document_designs" do
    path = Design::ThemeDbExportService.new(@theme).export!
    db = SQLite3::Database.new(path)
    db.results_as_hash = true
    row = db.execute("SELECT * FROM document_designs WHERE doc_type = 'toc'").first
    assert_equal "center", row["toc_v_align"]
  ensure
    db&.close
    File.delete(path) if path && File.exist?(path)
  end
end
