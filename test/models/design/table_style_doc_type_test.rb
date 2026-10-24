require "test_helper"
require "sqlite3"

# Table styles may belong to a document type (book_write's doc_type column). Without
# the column (the dummy schema, book_design) every row is a default, as before.
class Design::TableStyleDocTypeTest < ActiveSupport::TestCase
  include TypedTableStyles

  setup do
    @theme = Design::Theme.create!(name: "Typed #{SecureRandom.hex(3)}", locale: "ko") # seeds the five defaults
  end

  test "without the column, every row is a default and names are unique per theme" do
    refute Design::TableStyle.typed?
    assert_equal 5, @theme.table_styles.defaults.count
    refute @theme.table_styles.build(name: "zebra").valid?
  end

  test "a typed zebra coexists with the default zebra; a second one for the type doesn't" do
    add_table_style_doc_type!
    assert Design::TableStyle.typed?

    typed = @theme.table_styles.create!(name: "zebra", doc_type: "foreword")
    assert_equal [ typed ], @theme.table_styles.for_type("foreword").to_a
    assert_equal 5, @theme.table_styles.defaults.count
    assert_includes @theme.table_styles.build(name: "zebra", doc_type: "foreword").tap(&:valid?).errors[:name], "has already been taken"
    refute @theme.table_styles.build(name: "zebra").valid?, "a second default zebra"
    assert @theme.table_styles.build(name: "zebra", doc_type: "poem").valid?
    assert typed.valid?, "a row doesn't collide with itself"
  end

  test "the seeder and reset touch only the defaults" do
    add_table_style_doc_type!
    typed = @theme.table_styles.create!(name: "zebra", doc_type: "foreword", border_width: 7)
    @theme.table_styles.defaults.find_by!(name: "grid").destroy

    Design::ThemeStyleSeeder.call(@theme)
    assert_equal 5, @theme.table_styles.defaults.count
    assert_nil @theme.table_styles.defaults.find_by!(name: "grid").doc_type

    @theme.table_styles.defaults.find_by!(name: "zebra").update!(border_width: 99)
    Design::ThemeStyleSeeder.reset(@theme, "zebra")
    assert_equal 0.5, @theme.table_styles.defaults.find_by!(name: "zebra").border_width.to_f
    assert_equal 7, typed.reload.border_width.to_f
  end

  test "the export writes every row with its doc_type" do
    add_table_style_doc_type!
    @theme.table_styles.create!(name: "zebra", doc_type: "foreword")

    rows = exported_table_styles(@theme)
    assert_equal 6, rows.size
    assert_equal [ "foreword" ], rows.filter_map { _1["doc_type"] }
    assert_equal 5, rows.count { _1["doc_type"].nil? }
  end

  test "the export writes a nil doc_type without the column" do
    rows = exported_table_styles(@theme)
    assert_equal 5, rows.size
    assert rows.all? { _1.key?("doc_type") && _1["doc_type"].nil? }
  end

  test "a clone copies the typed rows too" do
    add_table_style_doc_type!
    @theme.table_styles.create!(name: "zebra", doc_type: "foreword", border_width: 7)

    cloned = Design::ThemeCloneService.new(@theme, user: users(:david)).clone
    assert_equal 5, cloned.table_styles.defaults.count
    assert_equal [ 7.0 ], cloned.table_styles.for_type("foreword").map { _1.border_width.to_f }
  end

  test "an import over a theme drops its typed rows and re-seeds the defaults" do
    add_table_style_doc_type!
    @theme.table_styles.create!(name: "zebra", doc_type: "foreword")

    service = Design::ThemeImportService.allocate
    service.send(:reset_children, @theme)
    Design::ThemeStyleSeeder.call(@theme)
    assert_equal 5, @theme.table_styles.count
    assert_empty @theme.table_styles.for_type("foreword")
  end

  private
    def exported_table_styles(theme)
      path = Design::ThemeDbExportService.new(theme).export!
      db = SQLite3::Database.new(path)
      db.results_as_hash = true
      db.execute("SELECT * FROM table_styles WHERE theme_id = ?", theme.id)
    ensure
      db&.close
      File.delete(path) if path && File.exist?(path)
    end
end
