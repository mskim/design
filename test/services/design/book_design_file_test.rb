require "test_helper"

# A .book_design (designcraft_rb's DesignCraftRb::BookDesign::Package) read into a single-size
# theme. These need no designcraft-cli: the inner book is written by hand
# (book_design_file_export_test lays real ones out).
class Design::BookDesignFileTest < ActiveSupport::TestCase
  LEGACY = Rails.root.join("test/fixtures/files/sample.book_design")
  PT = 72 / 25.4

  setup do
    require "designcraft_rb"
    @dir = Dir.mktmpdir("book_design_file_test")
  end

  teardown { FileUtils.rm_rf(@dir) }

  # --- the file and the old format -----------------------------------------------------------

  test "an old SQLite file imports through ThemeImportService" do
    theme = Design::BookDesignFile.import(LEGACY)
    assert_equal "classic", theme.name
    assert_equal "sample.book_design", theme.source_file
  end

  test "the file name names the theme and sets its language, as NFC" do
    nfd = "클래식".unicode_normalize(:nfd)
    theme = Design::BookDesignFile.import(write_file(nfd), font_dir: false)
    assert_equal [ "클래식", "ko" ], [ theme.name, theme.locale ]
    assert theme.name.unicode_normalized?(:nfc)

    assert_equal [ "Classic", "en" ], Design::BookDesignFile.import(write_file("Classic"), font_dir: false).then { [ it.name, it.locale ] }
    assert_equal "ja", Design::BookDesignFile.import(write_file("クラシック"), font_dir: false).locale
  end

  test "a package with an entry that could leave its folder is refused" do
    path = File.join(@dir, "evil.book_design")
    DesignCraftRb::ZipFile.write(path, { "mimetype" => DesignCraftRb::BookDesign::MIMETYPE, "../evil.txt" => "x",
                                         "manifest.json" => JSON.generate(manifest), "inner_page.designcraft" => inner_page_bytes })

    assert_raises(DesignCraftRb::BookDesign::Package::Invalid) { Design::BookDesignFile.import(path) }
    assert_not File.exist?(File.join(File.dirname(@dir), "evil.txt"))
    assert_not Design::Theme.exists?(name: "evil")
  end

  test "the size is the inner book's" do
    assert_equal [ 152.0, 225.0 ], Design::BookDesignFile.page_size_mm(document)
    assert_raises(Design::BookDesignFile::Error) { Design::BookDesignFile.page_size_mm({ "settings" => {} }) }
  end

  # --- styles read back ----------------------------------------------------------------------

  test "a document's styles read back as the app's" do
    styles = Design::BookDesignFile::Styles.new(document, font_dir: false)

    assert_equal "NotoSerifKR-Bold", styles.font_name("Noto Serif KR", "Bold")
    assert_equal "NotoSansKR-Regular", styles.font_name("CompositeFont/Noto Sans KR", nil)
    assert_equal "Courier", styles.font_name("Courier New", "Regular")
    assert_equal "TimesNewRoman", styles.font_name("Times New Roman", "Regular")
    assert_equal "CMYK=0,0,0,80", styles.color("K80")
    assert_equal "#cc3300", styles.color("#cc3300")
    assert_nil styles.color("[Black]")
    assert_nil styles.color(nil)

    h2 = styles.attributes("소제목", line_height: leading)
    assert_equal "NotoSerifKR-Bold", h2[:font]
    assert_equal 13.0, h2[:font_size]
    assert_equal "left", h2[:text_align]
    assert_equal 2, h2[:space_before_in_lines]
    assert_equal "CMYK=0,0,0,80", h2[:text_color], "from 본문, which it is based on"
    assert_nil h2[:font_style]
  end

  test "italic reads back as font_style italic with the upright face's name" do
    styles = Design::BookDesignFile::Styles.new(document, font_dir: false)

    # The engine's italic (slanted: Noto KR has no italic face), on a bold face.
    slanted = styles.attributes("인용", line_height: leading)
    assert_equal [ "NotoSerifKR-Bold", "italic" ], slanted.values_at(:font, :font_style)
    # An italic face.
    assert_equal [ "TimesNewRoman", "italic" ], styles.attributes("영문 기울임", line_height: leading).values_at(:font, :font_style)
    assert_equal [ "TimesNewRoman-Bold", "italic" ], styles.attributes("영문 굵은 기울임", line_height: leading).values_at(:font, :font_style)
  end

  test "a book font is named by its file" do
    skip "no book fonts" unless (dir = DesignCraftRb.font_dir)
    face = DesignCraftRb::DocProcessor::Styles.font_files(dir).find { |file, _| file == "smShinShinMyungjoP-30" } or skip "no smShinShinMyungjoP-30"

    assert_equal "smShinShinMyungjoP-30", Design::BookDesignFile::Styles.new(document, font_dir: dir).font_name(*face.last)
  end

  # --- loaded without the exporter's theme (an IDML or .designcraft import) -----------------

  test "a package without the exporter's theme makes a single-size theme from its inner book" do
    theme = Design::BookDesignFile.import(write_file("클래식"), font_dir: false)

    assert theme.system?
    assert_equal "클래식.book_design", theme.source_file
    assert_equal 1, theme.paper_sizes.count

    ps = theme.default_paper_size
    assert_equal [ 152, 225 ], [ ps.width_mm, ps.height_mm ]
    # The chapter's parent page, not the pages' own (inside → left, outside → right).
    assert_equal [ 18, 28, 25, 22, 0 ], [ ps.top_margin_mm, ps.bottom_margin_mm, ps.left_margin_mm, ps.right_margin_mm, ps.binding_margin_mm ].map { it.to_f.round(1) }
    assert_equal 23, ps.body_line_count

    body = theme.base_paragraph_styles.find_by!(name: "body")
    assert_equal [ "NotoSerifKR-Regular", 10.0, "justify", 10.0, -0.4, "CMYK=0,0,0,80", "본문" ],
                 [ body.font, body.font_size.to_f, body.text_align, body.first_line_indent.to_f, body.tracking.to_f, body.text_color, body.korean_name ]
    assert_nil body.text_line_spacing, "on the body grid"
    assert_equal 2, theme.base_paragraph_styles.find_by!(name: "h2").space_before_in_lines.to_i
    assert_equal "NotoSansKR-Black", theme.base_paragraph_styles.find_by!(name: "title").font
    assert_equal [ "NotoSerifKR-Regular", 10.0, "NotoSansKR-Black" ], [ theme.base_body_font, theme.base_body_font_size.to_f, theme.base_heading_font ]

    # Every doc type from the defaults; the chapter's columns from its pages.
    assert_equal Design::DocumentDesign::ALL_DOC_TYPES.sort, ps.document_designs.pluck(:doc_type).sort
    chapter = ps.document_designs.find_by!(doc_type: "chapter")
    assert_equal [ 2, 12.0 ], [ chapter.column_count, chapter.gutter.to_f ]
    # No generated (scaled) heading sizes over the book's.
    assert_equal 24.0, chapter.merged_paragraph_styles.find { it.name == "title" }.font_size.to_f
    assert theme.base_paragraph_styles.exists?(name: "publisher")
    assert theme.table_styles.exists?(name: "grid")
    assert File.exist?(theme.db_path)
  end

  test "loading again updates the theme in place; name and locale can be given" do
    path = write_file("클래식")
    first = Design::BookDesignFile.import(path, font_dir: false)
    again = Design::BookDesignFile.import(path, font_dir: false)
    assert_equal first.id, again.id
    assert_equal 1, again.paper_sizes.count

    english = Design::BookDesignFile.import(path, font_dir: false, name: "Classic", locale: "en")
    assert_not_equal first.id, english.id
    assert_equal [ "Classic", "en" ], [ english.name, english.locale ]
  end

  test "an imported theme of the same parameterized name and locale is updated, not duplicated" do
    legacy = Design::ThemeImportService.new(LEGACY).import!
    theme = Design::BookDesignFile.import(write_file("Classic"), font_dir: false, locale: "ko")
    assert_equal legacy.id, theme.id
    assert_equal "Classic", theme.name
  end

  test "a non-Latin name matches only a theme of that very name, not one it parameterizes like" do
    modern = Design::BookDesignFile.import(write_file("모던 2"), font_dir: false)
    assert_equal "2", "클래식 2".parameterize, "why: parameterize drops Hangul"

    classic = Design::BookDesignFile.import(write_file("클래식 2"), font_dir: false)
    assert_not_equal modern.id, classic.id
    assert_equal "클래식 2", classic.name

    modern.reload
    assert_equal [ "모던 2", "모던 2.book_design", 1 ], [ modern.name, modern.source_file, modern.paper_sizes.count ]
    assert modern.base_paragraph_styles.exists?(name: "body")
    # The same name in NFD is the same theme.
    assert_equal modern.id, Design::BookDesignFile.import(write_file("모던 2".unicode_normalize(:nfd)), font_dir: false).id
  end

  test "create_only refuses a name a system theme has, and creates one it doesn't" do
    assert_operator Design::BookDesignFile::NameTaken, :<, Design::BookDesignFile::Error
    created = Design::BookDesignFile.import(write_file("클래식"), font_dir: false, create_only: true)
    assert_equal "클래식", created.name
    imported_at = created.reload.imported_at

    assert_no_difference -> { Design::Theme.count } do
      assert_raises(Design::BookDesignFile::NameTaken) { Design::BookDesignFile.import(write_file("클래식"), font_dir: false, create_only: true) }
    end
    assert_equal imported_at, created.reload.imported_at
    assert_equal 1, created.paper_sizes.count

    # An all-ASCII name's parameterized match is taken too.
    legacy = Design::ThemeImportService.new(LEGACY).import!
    assert_raises(Design::BookDesignFile::NameTaken) do
      Design::BookDesignFile.import(write_file("Classic"), font_dir: false, locale: "ko", create_only: true)
    end
    assert_equal "classic", legacy.reload.name

    # Without it, the same files update.
    assert_equal created.id, Design::BookDesignFile.import(write_file("클래식"), font_dir: false).id
  end

  test "the body line count rounds down: a body line is never shorter than the book's leading" do
    fractional = ((225 - 18 - 28) * PT) / 23.6
    theme = Design::BookDesignFile.import(write_file("클래식", document: document(leading: fractional)), font_dir: false)
    ps = theme.default_paper_size
    assert_equal 23, ps.body_line_count
    assert_operator ps.body_line_height, :>=, fractional
  end

  test "a derived size is named as book_write finds it: a standard size's name, else its mm" do
    standard = Design::BookDesignFile.import(write_file("신국판", document: document(width: 151.8, height: 225.4)), font_dir: false)
    assert_equal [ "152mmx225mm", "신국판" ], standard.default_paper_size.then { [ it.size_name, it.local_name ] }

    custom = Design::BookDesignFile.import(write_file("별판", document: document(width: 140.5, height: 200.0)), font_dir: false)
    ps = custom.default_paper_size
    assert_equal [ 140.5, 200.0 ], [ ps.width_mm.to_f, ps.height_mm.to_f ]
    assert_equal [ "140.5mmx200mm", "140.5x200" ], [ ps.size_name, ps.local_name ]
  end

  test "h1 is no style: not a role, and no heading font comes from it" do
    roles = { "body" => "본문", "h1" => "장제목", "h2" => "소제목" }
    theme = Design::BookDesignFile.import(write_file("클래식", manifest: manifest.merge("styles" => roles)), font_dir: false)

    assert_not theme.base_paragraph_styles.exists?(name: "h1")
    assert_equal "NotoSerifKR-Bold", theme.base_heading_font, "h2's, not 장제목's"
  end

  test "an italic style loads where the host has no font_style column; the upright face is its font" do
    roles = manifest["styles"].merge("quote" => "인용")
    theme = Design::BookDesignFile.import(write_file("클래식", manifest: manifest.merge("styles" => roles)), font_dir: false)
    assert_equal "NotoSerifKR-Bold", theme.base_paragraph_styles.find_by!(name: "quote").font
  end

  private

  def leading = ((225 - 18 - 28) * PT) / 23

  def margins(top, bottom, inside, outside) = { "top" => top * PT, "bottom" => bottom * PT, "inside" => inside * PT, "outside" => outside * PT }

  def page(id, side, parent: nil, columns: 1, gutter: 10.0)
    { "id" => id, "width" => 152 * PT, "height" => 225 * PT, "side" => side, "parent" => parent,
      "margins" => margins(10, 10, 10, 10), "columns" => { "count" => columns, "gutter" => gutter } }.compact
  end

  # A document as DesignCraft saves one, cut down: a title page and a two-page chapter on
  # parent A, whose margins differ from the pages' own. width/height: the pages' (mm).
  def document(width: 152, height: 225, leading: self.leading)
    {
      "title" => "클래식",
      "settings" => { "pageWidth" => width * PT, "pageHeight" => height * PT, "facingPages" => true,
                      "baselineGrid" => { "start" => 18 * PT, "increment" => leading } },
      "parents" => [ { "id" => 4, "items" => [], "parent" => { "prefix" => "A", "name" => "chapter" },
                       "pages" => [ page(2, "left").merge("margins" => margins(18, 28, 25, 22)),
                                    page(3, "right").merge("margins" => margins(18, 28, 25, 22)) ] } ],
      "spreads" => [ { "id" => 10, "items" => [], "pages" => [ page(11, "right") ] },
                     { "id" => 12, "items" => [], "pages" => [ page(13, "left", parent: 4, columns: 2, gutter: 12.0),
                                                              page(14, "right", parent: 4, columns: 2, gutter: 12.0) ] } ],
      "styles" => { "paragraph" => [
        { "name" => "[No Paragraph Style]", "para" => {}, "chars" => {} },
        { "name" => "[Basic Paragraph]", "para" => {}, "chars" => { "fontFamily" => "Noto Serif KR" } },
        { "name" => "본문", "basedOn" => "[Basic Paragraph]",
          "para" => { "align" => "leftJustified", "firstLineIndent" => 10.0, "spaceBefore" => 0.0 },
          "chars" => { "size" => 10.0, "leading" => { "kind" => "points", "value" => leading }, "tracking" => -40.0, "fill" => "K80" } },
        { "name" => "소제목", "basedOn" => "본문",
          "para" => { "align" => "left", "spaceBefore" => 2 * leading, "firstLineIndent" => 0.0 },
          "chars" => { "fontStyle" => "Bold", "size" => 13.0 } },
        { "name" => "장제목", "basedOn" => "[Basic Paragraph]", "para" => { "align" => "center" },
          "chars" => { "fontFamily" => "Noto Sans KR", "fontStyle" => "Black", "size" => 24.0 } },
        { "name" => "인용", "basedOn" => "본문", "chars" => { "fontStyle" => "Bold", "italic" => true } },
        { "name" => "영문 기울임", "basedOn" => "본문", "chars" => { "fontFamily" => "Times New Roman", "fontStyle" => "Italic" } },
        { "name" => "영문 굵은 기울임", "basedOn" => "본문", "chars" => { "fontFamily" => "Times New Roman", "fontStyle" => "Bold Italic" } }
      ] },
      "swatches" => [
        { "name" => "[Black]", "value" => { "kind" => "color", "color" => { "model" => "cmyk", "c" => 0.0, "m" => 0.0, "y" => 0.0, "k" => 1.0 } } },
        { "name" => "K80", "value" => { "kind" => "color", "color" => { "model" => "cmyk", "c" => 0, "m" => 0, "y" => 0, "k" => 0.8 } } },
        { "name" => "#cc3300", "value" => { "kind" => "color", "color" => { "model" => "rgb", "r" => 0.8, "g" => 0.2, "b" => 0.0 } } }
      ]
    }
  end

  def manifest
    { "format" => "book_design", "version" => DesignCraftRb::BookDesign::VERSION,
      "page_size" => { "width_mm" => 152.0, "height_mm" => 225.0 },
      "doc_types" => { "title_page" => { "first_page" => 0, "page_count" => 1 }, "chapter" => { "first_page" => 1, "page_count" => 2 } },
      "styles" => { "body" => "본문", "h2" => "소제목", "title" => "장제목" } }
  end

  def inner_page_bytes(document = self.document)
    path = File.join(@dir, "inner.designcraft")
    DesignCraftRb::ZipFile.write(path, { "mimetype" => "application/vnd.designcraft+zip", "document.json" => JSON.generate(document) })
    File.binread(path)
  end

  def write_file(name, document: self.document, manifest: self.manifest)
    inner = File.join(@dir, "inner_page.designcraft")
    File.binwrite(inner, inner_page_bytes(document))
    DesignCraftRb::BookDesign::Package.write(name: name, inner_page: inner, manifest: manifest, to: File.join(@dir, "out"))
  end
end
