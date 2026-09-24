require "test_helper"
require "sqlite3"

class Design::ThemeImportServiceTest < ActiveSupport::TestCase
  FIXTURE = Rails.root.join("test/fixtures/files/sample.book_design")

  test "imports a .book_design file as a system theme matched by parameterized name" do
    theme = Design::ThemeImportService.new(FIXTURE).import!
    assert theme.system?, "imported theme must be a system theme (user_id nil)"
    assert_equal "classic", theme.name           # parameterized from "Classic"
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
    # Import normalises (a doc-type row whose every field equals its parent is
    # dropped). The fixture's 3 chapter rows (body, styled_para, title) each
    # differ from the base in some field, so exactly those 3 remain (a generator
    # row of the same name is overwritten by the imported one).
    assert_equal 3, src[:ddps]
    assert_equal %w[body styled_para title],
      Design::ParagraphStyle.where(styleable_type: "Design::DocumentDesign", styleable_id: theme.document_designs.ids).pluck(:name).sort

    body = theme.base_paragraph_styles.find_by(name: "body")
    assert_in_delta 9.5, body.font_size.to_f, 0.001
    assert_equal "justify", body.text_align
  end

  test "importing a full-snapshot .book_design yields sparse doc-type rows" do
    # The fixture's chapter `body` row repeats the theme base (font, size, align,
    # colour) and adds first_line_indent — a full snapshot.
    theme = Design::ThemeImportService.new(FIXTURE).import!

    chapter = theme.document_designs.find_by(doc_type: "chapter")
    body = chapter.paragraph_styles.find_by(name: "body")
    assert_not_nil body, "row with a differing field is kept"
    assert_in_delta 9.5, body.first_line_indent.to_f, 0.001
    %w[font font_size text_align text_color].each do |f|
      assert_nil body[f], "#{f} equals the theme base, so it is inherited (nil)"
    end

    theme.document_designs.each do |dd|
      dd.paragraph_styles.each do |row|
        parent = dd.parent_values(row.name)
        Design::ParagraphStyle::STYLE_FIELDS.each do |f|
          next if row[f].nil?
          refute Design::ParagraphStyle.same_value?(f, row[f], parent[f]),
            "#{dd.doc_type}/#{row.name}.#{f} repeats its parent"
        end
      end
    end

    # Resolution is unchanged: the chapter still renders the snapshot's values.
    resolved = chapter.merged_paragraph_styles.find { |s| s.name == "body" }
    assert_equal "smShinShinMyungjoP-30", resolved.font
    assert_in_delta 9.5, resolved.font_size.to_f, 0.001
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

    # A host Book references the theme by its stable "design_theme_<id>" token.
    # (The real Book/PdfBookInfo models live in book_write, not in this engine;
    # the full Book→PdfBookInfo round-trip is covered by book_write's own suite.
    # Here we verify the engine guarantee that makes those references stable:
    # re-import keeps the theme id, so a stored "design_theme_<id>" still resolves.)
    book_theme_token = "design_theme_#{id}"

    theme2 = Design::ThemeImportService.new(FIXTURE).import!

    assert_equal id, theme2.id, "re-import must preserve the theme id"
    assert_equal 1, Design::Theme.system_themes.where(name: "classic").count, "no duplicate theme"
    resolved = Design::Theme.find(book_theme_token.delete_prefix("design_theme_").to_i)
    assert_equal id, resolved.id
    assert_equal theme1.paper_sizes.count, theme2.paper_sizes.count
  end

  test "re-importing a theme updates the row with the same name AND locale, keeping its id" do
    # The English row is created FIRST: the old name-only lookup returns the
    # lowest id, so this is what makes the test fail before the fix.
    other_language = Design::Theme.create!(name: "baroque", locale: "en")
    existing = Design::Theme.create!(name: "baroque", locale: "ko")
    Dir.mktmpdir do |dir|
      path = File.join(dir, "baroque-ko.book_design")
      FileUtils.cp(FIXTURE, path)
      SQLite3::Database.new(path) { |db| db.execute("UPDATE theme SET name = 'Baroque', locale = 'ko'") }
      theme = Design::ThemeImportService.new(path).import!
      assert_equal existing.id, theme.id
    end
    assert_equal "en", other_language.reload.locale, "the English one is untouched"
    assert_equal 1, Design::Theme.system_themes.where(name: "baroque", locale: "ko").count
  ensure
    Dir.glob(File.join(Design.themes_dir.to_s, "baroque-*.db")).each { |f| File.delete(f) }
  end

  # The fixture's one bordered style is a document-design row "styled_para":
  # 0.3 pt on all four sides (1,1,1,1), all four corners medium.
  test "a pre-D5 file's borders arrive as the twelve fields" do
    theme = Design::ThemeImportService.new(file_fixture("sample.book_design")).import!
    boxed = theme.document_designs.flat_map { |dd| dd.paragraph_styles.where(name: "styled_para").to_a }.first
    assert boxed, "the fixture's bordered style"
    assert_equal [ 0.3 ] * 4, Design::ParagraphStyle::BORDER_THICKNESS_FIELDS.map { |f| boxed[f].to_f }
    assert_equal %w[medium] * 4, Design::ParagraphStyle::CORNER_FIELDS.map { |f| boxed[f] }
  end

  # A schema-3 file (the fixture plus the twelve columns) imports them as they
  # are: its old five are ignored, nothing is converted.
  test "a D5 file's twelve fields import unchanged" do
    file = Tempfile.new([ "d5", ".book_design" ])
    FileUtils.cp(FIXTURE, file.path)
    db = SQLite3::Database.new(file.path)
    Design::ParagraphStyle::BORDER_FIELDS.each do |f|
      type = Design::ParagraphStyle::BORDER_THICKNESS_FIELDS.include?(f) ? "REAL" : "TEXT"
      db.execute("ALTER TABLE paragraph_styles ADD COLUMN #{f} #{type}")
    end
    db.execute("UPDATE metadata SET value = '3' WHERE key = 'schema_version'")
    db.execute("UPDATE paragraph_styles SET border_top_thickness = 1.5, border_left_color = '#ff0000', " \
               "corner_bottom_right = 'full' WHERE styleable_type = 'theme' AND name = 'body'")
    db.execute("UPDATE paragraph_styles SET border_right_thickness = 2, corner_top_left = 'small' " \
               "WHERE name = 'styled_para'")
    db.close

    theme = Design::ThemeImportService.new(file.path).import!
    base = theme.base_paragraph_styles.find_by(name: "body")
    assert_in_delta 1.5, base.border_top_thickness.to_f, 0.001
    assert_equal "#ff0000", base.border_left_color
    assert_equal "full", base.corner_bottom_right
    assert_nil base.border_bottom_thickness, "unset fields stay unset"

    boxed = theme.document_designs.flat_map { |dd| dd.paragraph_styles.where(name: "styled_para").to_a }.first
    assert_in_delta 2.0, boxed.border_right_thickness.to_f, 0.001
    assert_equal "small", boxed.corner_top_left
    assert_nil boxed.border_top_thickness, "the old 0.3 pt was not converted"
    assert_nil boxed.corner_top_right, "the old medium corners were not converted"
  ensure
    file&.close!
  end
end
