require "test_helper"
require "sqlite3"

# After the D4 crop fix, reading order means 2 is top centre — the default that
# keeps a portrait photo's head in view. The column default and the exported
# .db's DDL default must agree, or a new design and a rebaked theme would
# disagree about the same photo. (The engine's own fallback is covered by the
# engine suite; reading its source from here would only work through the local
# bundler override.)
class Design::PhotoAnchorDefaultTest < ActiveSupport::TestCase
  test "a new design's photo_anchor is 2" do
    theme = Design::Theme.create!(name: "PA #{SecureRandom.hex(3)}", locale: "ko")
    ps = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    assert_equal 2, ps.document_designs.create!(doc_type: "front_wing").photo_anchor
    assert_equal 2, Design::DocumentDesign.column_defaults["photo_anchor"]
  end

  # The DDL is an inline heredoc in ThemeDbExportService#create_tables (no
  # constant to read), so assert against a real exported .db — the pattern
  # theme_db_export_service_test.rb already uses.
  test "the exported .db declares the same default" do
    theme = Design::Theme.create!(name: "PA2 #{SecureRandom.hex(3)}", locale: "ko")
    path = Design::ThemeDbExportService.new(theme).export!
    db = SQLite3::Database.new(path)
    column = db.execute("PRAGMA table_info(document_designs)").find { |c| c[1] == "photo_anchor" }
    assert_equal "2", column[4].to_s, "the DDL's DEFAULT"
  ensure
    db&.close
    File.delete(path) if path && File.exist?(path)
  end
end
