require "test_helper"

# A theme's size exported as a .book_design (its samples laid out by DesignCraft) and read
# back: the round trip a design makes between book_design and book_write.
class Design::BookDesignFileExportTest < ActiveSupport::TestCase
  LEGACY = Rails.root.join("test/fixtures/files/sample.book_design")

  setup { @dir = Dir.mktmpdir("book_design_export_test") }
  teardown { FileUtils.rm_rf(@dir) }

  def designcraft_cli!
    require "designcraft_rb"
    DesignCraftRb::Client.find_cli
  rescue LoadError, DesignCraftRb::CliNotFound => e
    skip e.message
  end

  def open(path, &) = DesignCraftRb::BookDesign::Package.open(path, &)

  # The fixture's Classic (title page, copyright, chapter on 128 × 188 mm), named in Korean.
  def classic
    Design::ThemeImportService.new(LEGACY).import!.tap { it.update!(name: "클래식") }
  end

  test "export, open, load: the same size, margins and styles under the file's name" do
    designcraft_cli!
    theme = classic
    ps = theme.default_paper_size
    chapter_body = -> { it.document_designs.find_by!(doc_type: "chapter").merged_paragraph_styles.find { |s| s.name == "body" }.attributes.slice("font", "font_size", "first_line_indent", "tracking") }
    before = {
      margins: ps.attributes.slice(*Design::PaperSize::GENERATABLE_FIELDS).transform_values(&:to_s),
      body: theme.base_paragraph_styles.find_by!(name: "body").attributes.slice(*Design::ParagraphStyle::STYLE_FIELDS),
      chapter_body: chapter_body.(ps),
      doc_types: ps.document_designs.pluck(:doc_type).sort,
      heading_elements: Design::HeadingElement.where(document_design_id: ps.document_designs.ids).count
    }

    exporter = Design::BookDesignFile::Exporter.new(theme, cover: false)
    path = exporter.export!(@dir)
    assert_equal File.join(@dir, "클래식.book_design"), path
    assert exporter.locale_from_name?

    open(path) do |file|
      assert_equal [ "클래식", "ko" ], [ file.name, file.locale ]
      assert_equal [ 128.0, 188.0 ], Design::BookDesignFile.page_size_mm(file.document)
      assert_equal %w[title_page copyright chapter], file.doc_types.keys, "in reading order"
      ranges = file.doc_types.values
      assert_equal 0, ranges.first.first_page
      ranges.each_cons(2) { |a, b| assert_equal a.last_page + 1, b.first_page }
      assert_equal ranges.last.last_page + 1, file.page_count
      assert_equal "body", file.styles["body"]
      assert_equal "title", file.styles["title"]
      assert_nil file.book_cover_path
      assert_equal "클래식", file.manifest.dig("theme", "theme", "name")
    end

    loaded = Design::BookDesignFile.import(path)
    assert_equal theme.id, loaded.id, "the same name and locale: updated in place"
    assert_equal [ "클래식", "ko" ], [ loaded.name, loaded.locale ]
    lps = loaded.default_paper_size
    assert_equal 1, loaded.paper_sizes.count
    assert_equal [ 128, 188 ], [ lps.width_mm, lps.height_mm ]
    assert_equal before[:margins], lps.attributes.slice(*Design::PaperSize::GENERATABLE_FIELDS).transform_values(&:to_s)
    assert_equal before[:body], loaded.base_paragraph_styles.find_by!(name: "body").attributes.slice(*Design::ParagraphStyle::STYLE_FIELDS)
    assert_equal before[:chapter_body], chapter_body.(lps)
    assert_equal before[:doc_types], lps.document_designs.pluck(:doc_type).sort
    assert_equal before[:heading_elements], Design::HeadingElement.where(document_design_id: lps.document_designs.ids).count
    assert File.exist?(loaded.db_path)
  end

  test "without the theme rows, the inner book alone gives back the size, margins and body" do
    designcraft_cli!
    theme = classic
    ps = theme.default_paper_size
    path = Design::BookDesignFile::Exporter.new(theme, cover: false).export!(@dir)

    # As an IDML import would give it: the inner book and the manifest's ranges, no theme.
    bare = open(path) do |file|
      DesignCraftRb::BookDesign::Package.write(name: "클래식 사본", inner_page: file.inner_page_path, to: File.join(@dir, "bare"),
                                               manifest: file.manifest.except("theme"))
    end

    derived = Design::BookDesignFile.import(bare)
    assert_not_equal theme.id, derived.id
    dps = derived.default_paper_size
    assert_equal [ 128, 188 ], [ dps.width_mm, dps.height_mm ]
    assert_in_delta ps.top_margin_mm, dps.top_margin_mm, 0.01
    assert_in_delta ps.bottom_margin_mm, dps.bottom_margin_mm, 0.01
    # DesignCraft's inside margin is the left margin and the binding.
    assert_in_delta ps.left_margin_mm + ps.binding_margin_mm, dps.left_margin_mm, 0.01
    assert_in_delta ps.right_margin_mm, dps.right_margin_mm, 0.01
    assert_equal ps.body_line_count, dps.body_line_count

    body = derived.base_paragraph_styles.find_by!(name: "body")
    source = ps.document_designs.find_by!(doc_type: "chapter").merged_paragraph_styles.find { it.name == "body" }
    assert_equal source.font, body.font
    assert_in_delta source.font_size, body.font_size, 0.001
    assert_in_delta source.first_line_indent, body.first_line_indent, 0.001
    assert_in_delta source.tracking, body.tracking, 0.01
    assert_equal source.text_align, body.text_align
  end

  test "a name that doesn't give the locale: locale_from_name? says so and Loader takes locale:" do
    designcraft_cli!
    theme = Design::ThemeImportService.new(LEGACY).import! # "classic", ko
    exporter = Design::BookDesignFile::Exporter.new(theme, cover: false)
    assert_equal "classic.book_design", exporter.file_name
    assert_not exporter.locale_from_name?

    path = exporter.export!(@dir)
    assert_equal "en", open(path, &:locale)
    assert_equal theme.id, Design::BookDesignFile.import(path, locale: theme.locale).id
  end

  test "the cover panels make book_cover.designcraft, one spread" do
    designcraft_cli!
    theme = Design::Theme.create!(name: "표지 #{SecureRandom.hex(2)}", locale: "ko")
    ps = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    Design::PaperSizeSeeder.call(ps)
    ps.document_designs.where.not(doc_type: Design::DocumentDesign::COVER_PANEL_TYPES + %w[chapter]).destroy_all

    open(Design::BookDesignFile.export(theme, to: @dir)) do |file|
      assert_equal Design::DocumentDesign::COVER_PANEL_ORDER, file.cover["panels"].keys
      assert_equal 2, file.cover.dig("panels", "seneca", "first_page")
      cover = JSON.parse(DesignCraftRb::ZipFile.read(file.book_cover_path).fetch("document.json"))
      assert_equal 1, cover["spreads"].size
      assert_equal 5, cover["spreads"].first["pages"].size
      assert_equal %w[chapter], file.doc_types.keys
    end
  end

  test "a theme without a chapter design is refused" do
    designcraft_cli!
    theme = Design::Theme.create!(name: "Empty #{SecureRandom.hex(2)}", locale: "en")
    theme.paper_sizes.create!(size_name: "A5", width_mm: 148, height_mm: 210).document_designs.create!(doc_type: "toc")
    assert_raises(ArgumentError) { Design::BookDesignFile::Exporter.new(theme, cover: false).export!(@dir) }
  end
end
