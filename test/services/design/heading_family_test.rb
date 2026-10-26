require "test_helper"
require "sqlite3"

# publisher joins the heading family; title pages get their own scaled heading
# sizes, preview the four by name, and an import from before the change is
# separated (spec 2026-10-26 §5).
class Design::HeadingFamilyTest < ActiveSupport::TestCase
  FIXTURE = Rails.root.join("test/fixtures/files/sample.book_design")
  R = Design::GenerationRules

  test "publisher is in the heading family; chapter's scaled sizes leave it out" do
    assert_includes R::HEADING, "publisher"
    # Covers read publisher theme → chapter → piece: a generated chapter row would reach them.
    assert_not_includes R::HEADING_SCALED_STYLES, "publisher"
    assert_includes Design::DocumentDesign::STYLE_FAMILIES[:heading], "publisher"
  end

  test "a new theme has a theme-level publisher: body's font, size and colour, centred, nothing else" do
    theme = Design::Theme.create!(name: "Pub #{SecureRandom.hex(3)}", locale: "ko", base_body_font: "Body", base_body_font_size: 9.5)
    pub = theme.base_paragraph_styles.find_by(name: "publisher")
    assert pub
    assert_equal [ "Body", 9.5, "center" ], [ pub.font, pub.font_size.to_f, pub.text_align ]
    (Design::ParagraphStyle::STYLE_FIELDS - %w[font font_size text_color text_align]).each { assert_nil pub[it], it }
  end

  test "the seeder takes publisher from the theme's body row when there is one, and is idempotent" do
    theme = Design::Theme.create!(name: "Pub #{SecureRandom.hex(3)}", locale: "ko")
    theme.base_paragraph_styles.where(name: "publisher").delete_all
    theme.base_paragraph_styles.create!(name: "body", font: "BodyRow", font_size: 10.5, text_color: "CMYK=0,0,0,80")
    Design::ThemeStyleSeeder.call(theme)
    Design::ThemeStyleSeeder.call(theme)
    pubs = theme.base_paragraph_styles.where(name: "publisher")
    assert_equal 1, pubs.count
    assert_equal [ "BodyRow", 10.5, "CMYK=0,0,0,80" ], [ pubs.first.font, pubs.first.font_size.to_f, pubs.first.text_color ]
  end

  test "seeding a theme from before the change, one with designs, separates it instead of only marking it" do
    theme = Design::Theme.create!(name: "Old #{SecureRandom.hex(3)}", locale: "ko")
    theme.base_paragraph_styles.create!(name: "subtitle", font_size: 16)
    ps = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    ch = ps.document_designs.create!(doc_type: "chapter")
    tp = ps.document_designs.create!(doc_type: "title_page")
    Design::ParagraphStyle.where(styleable: [ ch, tp ]).delete_all
    theme.base_paragraph_styles.where(name: "publisher").delete_all
    ch.paragraph_styles.create!(name: "subtitle", font_size: 13.5)

    Design::ThemeStyleSeeder.call(theme)
    assert theme.base_paragraph_styles.exists?(name: "publisher")
    assert_equal 13.5, tp.paragraph_styles.find_by(name: "subtitle")&.font_size.to_f, "what the title page printed through chapter"
  end

  test "each title-page kind gets the scaled sizes of the four; chapter-like kinds don't" do
    theme = Design::Theme.create!(name: "Gen #{SecureRandom.hex(3)}", locale: "ko", base_body_font_size: 10)
    { "title" => 24, "subtitle" => 16, "author" => 12, "h2" => 14 }.each { |n, s| theme.base_paragraph_styles.create!(name: n, font_size: s) }
    ps = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    %w[chapter title_page inside_cover part_cover foreword thanks].each { ps.document_designs.create!(doc_type: it) }

    Design::DocumentDesign::TITLE_PAGE_KINDS.each do |kind|
      rows = ps.document_designs.find_by(doc_type: kind).paragraph_styles.index_by(&:name)
      assert_equal %w[author publisher subtitle title], rows.keys.sort, kind
      assert_equal [ 18.0, 12.0, 9.0, 7.5 ], %w[title subtitle author publisher].map { rows[it].font_size.to_f }, kind
    end
    assert_nil ps.document_designs.find_by(doc_type: "chapter").paragraph_styles.find_by(name: "publisher"),
               "chapter gets no generated publisher"
    %w[foreword thanks].each { assert_empty ps.document_designs.find_by(doc_type: it).paragraph_styles, it }
  end

  test "the generator leaves a title-page font_size marked overridden" do
    theme = Design::Theme.create!(name: "Gen #{SecureRandom.hex(3)}", locale: "ko")
    theme.base_paragraph_styles.create!(name: "title", font_size: 24)
    ps = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    tp = ps.document_designs.create!(doc_type: "title_page")
    row = tp.paragraph_styles.find_by(name: "title")
    row.update!(font_size: 30); row.mark_overridden(:font_size)
    Design::DefaultGenerator.call(ps)
    assert_equal 30, row.reload.font_size.to_i
  end

  test "the preview passes the four by their own names on a title page, centred, no indent, with no aliases" do
    theme = Design::Theme.create!(name: "Pv #{SecureRandom.hex(3)}", locale: "ko")
    theme.base_paragraph_styles.create!(name: "subtitle", font_size: 16, first_line_indent: 5)
    theme.base_paragraph_styles.create!(name: "body", font_size: 10, text_align: "justify", first_line_indent: 10)
    theme.base_paragraph_styles.create!(name: "h2", font_size: 14, text_align: "left")
    ps = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    %w[chapter inside_cover].each { ps.document_designs.create!(doc_type: it) }
    out = styles_for(ps, "inside_cover")

    assert_equal "center", out["subtitle"]["text_align"]
    assert_equal 0.0, out["subtitle"]["first_line_indent"]
    assert_equal "center", out["publisher"]["text_align"]
    assert_equal 14.0, out["h2"]["font_size"].to_f, "h2 is the real h2"
    assert_equal "justify", out["body"]["text_align"], "body is the real body"
    assert_equal 10.0, out["body"]["first_line_indent"]
    assert_nil out["h1"], "no title→h1 copy"
  end

  test "a chapter preview keeps the styles as they resolve" do
    theme = Design::Theme.create!(name: "Pv #{SecureRandom.hex(3)}", locale: "ko")
    theme.base_paragraph_styles.create!(name: "subtitle", font_size: 16, text_align: "left", first_line_indent: 5)
    ps = theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    ps.document_designs.create!(doc_type: "chapter")
    out = styles_for(ps, "chapter")
    assert_equal "left", out["subtitle"]["text_align"]
    assert_equal 5.0, out["subtitle"]["first_line_indent"]
  end

  test "an import from before the change is separated: title pages keep what they printed" do
    theme = Design::ThemeImportService.new(FIXTURE).import!
    assert theme.base_paragraph_styles.exists?(name: "publisher")
    title = theme.document_designs.find_by(doc_type: "title_page").paragraph_styles.find_by(name: "title")
    assert title, "the chapter's title is copied onto the title page"
    assert_equal [ "NotoSerifKR-Bold", 24.0, "center" ], [ title.font, title.font_size.to_f, title.text_align ]
  ensure
    File.delete(theme.db_path) if theme && File.exist?(theme.db_path)
  end

  test "an import whose file has the theme-level publisher is not separated" do
    path = Rails.root.join("tmp", "with_publisher_#{SecureRandom.hex(3)}.book_design")
    FileUtils.mkdir_p(File.dirname(path))
    FileUtils.cp(FIXTURE, path)
    db = SQLite3::Database.new(path.to_s)
    db.execute("INSERT INTO paragraph_styles (styleable_type, styleable_id, name, font, font_size, text_align) VALUES ('theme', 0, 'publisher', 'P', 9, 'center')")
    db.close

    theme = Design::ThemeImportService.new(path).import!
    assert_equal "P", theme.base_paragraph_styles.find_by(name: "publisher").font
    assert_nil theme.document_designs.find_by(doc_type: "title_page").paragraph_styles.find_by(name: "title")
  ensure
    FileUtils.rm_f(path) if path
    File.delete(theme.db_path) if theme && File.exist?(theme.db_path)
  end

  test "a clone copies the source's publisher row, not a seeded one" do
    source = Design::Theme.create!(name: "Src #{SecureRandom.hex(3)}", locale: "ko")
    source.base_paragraph_styles.find_by(name: "publisher").update!(font: "Custom")
    copy = Design::ThemeCloneService.new(source, user: User.first).clone
    assert_equal [ "Custom" ], copy.base_paragraph_styles.where(name: "publisher").pluck(:font)
  end

  private

  # The styles populate_paragraph_styles hands the layout: { name => attributes }.
  def styles_for(ps, doc_type)
    dd = ps.document_designs.find_by(doc_type: doc_type)
    out = Class.new do
      attr_reader :styles
      def initialize = @styles = {}
      def clear_styles = @styles.clear
      def delete_style(name) = @styles.delete(name)
      def add_style(name:, display_name:, attributes:) = @styles[name] = JSON.parse(attributes)
    end.new
    Design::PreviewService.new(dd, paper_size: ps).send(:populate_paragraph_styles, out)
    out.styles.transform_values { it.transform_keys(&:to_s) }
  end
end
