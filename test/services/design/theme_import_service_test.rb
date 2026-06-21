require "test_helper"
require "sqlite3"

class Design::ThemeImportServiceTest < ActiveSupport::TestCase
  FIXTURE = Rails.root.join("test/fixtures/files/sample.book_design")

  test "imports a .book_design file as a system theme matched by parameterized name" do
    theme = Design::ThemeImportService.new(FIXTURE).import!
    assert theme.system?, "imported theme must be a system theme (user_id nil)"
    assert_equal "seoul", theme.name           # parameterized from "Seoul"
    assert theme.imported?
    assert_equal "sample.book_design", theme.source_file
  end

  test "reconstructs the full theme graph matching the source file" do
    db = SQLite3::Database.new(FIXTURE.to_s); db.results_as_hash = true
    src = {
      base:  db.get_first_value("SELECT count(*) FROM paragraph_styles WHERE styleable_type='theme'"),
      ps:    db.get_first_value("SELECT count(*) FROM paper_sizes"),
      dd:    db.get_first_value("SELECT count(*) FROM document_designs"),
      he:    db.get_first_value("SELECT count(*) FROM heading_elements"),
      ddps:  db.get_first_value("SELECT count(*) FROM paragraph_styles WHERE styleable_type='document_design'")
    }
    db.close

    theme = Design::ThemeImportService.new(FIXTURE).import!

    # ThemeStyleSeeder (run at the end of import!) adds table_heading_cell +
    # table_body_cell, which .book_design v2 does not carry — hence +2.
    assert_equal src[:base] + 2, theme.base_paragraph_styles.count
    # the source's own theme-level styles are all imported:
    assert theme.base_paragraph_styles.exists?(name: "body")
    assert_equal src[:ps],   theme.paper_sizes.count
    assert_equal src[:dd],   theme.document_designs.count
    assert_equal src[:he],   Design::HeadingElement.where(document_design_id: theme.document_designs.ids).count
    assert_equal src[:ddps], Design::ParagraphStyle.where(styleable_type: "Design::DocumentDesign", styleable_id: theme.document_designs.ids).count

    body = theme.base_paragraph_styles.find_by(name: "body")
    assert_in_delta 9.5, body.font_size.to_f, 0.001
    assert_equal "justify", body.text_align
  end

  test "rejects an unsupported schema version without writing partial records" do
    bad = Tempfile.new(["bad", ".book_design"])
    db = SQLite3::Database.new(bad.path)
    db.execute("CREATE TABLE metadata(key TEXT, value TEXT)")
    db.execute("INSERT INTO metadata VALUES('schema_version','999')")
    db.execute("CREATE TABLE theme(name TEXT)")
    db.execute("INSERT INTO theme VALUES('Broken')")
    db.close
    before = Design::Theme.count
    assert_raises(Design::ThemeImportService::UnsupportedSchemaVersion) do
      Design::ThemeImportService.new(bad.path).import!
    end
    assert_equal before, Design::Theme.count
  ensure
    bad&.close!
  end

  test "rejects a file with no schema_version metadata, writing nothing" do
    bad = Tempfile.new(["nover", ".book_design"])
    db = SQLite3::Database.new(bad.path)
    db.execute("CREATE TABLE metadata(key TEXT, value TEXT)")
    db.execute("CREATE TABLE theme(name TEXT)"); db.execute("INSERT INTO theme VALUES('NoVer')")
    db.close
    before = Design::Theme.count
    assert_raises(Design::ThemeImportService::UnsupportedSchemaVersion) do
      Design::ThemeImportService.new(bad.path).import!
    end
    assert_equal before, Design::Theme.count
  ensure
    bad&.close!
  end

  test "import_all imports every .book_design in a directory" do
    count = Dir.glob(Rails.root.join("db/themes_source/*.book_design")).size
    assert_operator count, :>=, 1
    themes = Design::ThemeImportService.import_all
    assert_equal count, themes.size
    assert themes.all?(&:system?)
  end

  test "imported theme exports a valid render .db" do
    theme = Design::ThemeImportService.new(FIXTURE).import!
    path = Design::ThemeDbExportService.new(theme).export!
    db = SQLite3::Database.new(path); db.results_as_hash = true
    assert_operator db.get_first_value("SELECT count(*) FROM paper_sizes"), :>=, 1
    assert_operator db.get_first_value("SELECT count(*) FROM paragraph_styles"), :>=, 1
  ensure
    db&.close
    File.delete(path) if path && File.exist?(path)
  end

  test "re-import updates in place, preserving the theme id and book references" do
    theme1 = Design::ThemeImportService.new(FIXTURE).import!
    id = theme1.id
    book = Book.create!(title: "Ref", book_type: "novel")
    book.create_pdf_book_info!(size: "신국판", theme: "design_theme_#{id}")

    theme2 = Design::ThemeImportService.new(FIXTURE).import!

    assert_equal id, theme2.id, "re-import must preserve the theme id"
    assert_equal 1, Design::Theme.system_themes.where(name: "seoul").count, "no duplicate theme"
    resolved = Design::Theme.find(book.reload.pdf_book_info.theme.delete_prefix("design_theme_").to_i)
    assert_equal id, resolved.id
    assert_equal theme1.paper_sizes.count, theme2.paper_sizes.count
  end
end
