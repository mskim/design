require "test_helper"
require "sqlite3"

# The fill of spec 2026-10-26 §6: what title-page kinds print today (theme →
# chapter → kind, renamed to h1/h2/h3/body by book_write's heading_aliases) is
# copied onto each kind's own title/subtitle/author/publisher rows, so that the
# new resolution (theme → kind, the real names) prints the same.
class Design::HeadingStyleSeparationTest < ActiveSupport::TestCase
  KINDS = %w[title_page inside_cover part_cover].freeze
  ALIASES = { "title" => "h1", "subtitle" => "h2", "author" => "h3", "publisher" => "body" }.freeze
  ATTRS = Design::DocumentDesign::MERGEABLE_ATTRS
  # What the heading stack reads of publisher (a body fallback drops the rest).
  NOT_COMPARED = { "publisher" => %w[korean_name space_before_in_lines space_after_in_lines first_line_indent dropcap] }.freeze

  setup do
    @theme = Design::Theme.create!(name: "Sep #{SecureRandom.hex(3)}", locale: "ko")
    @theme.base_paragraph_styles.where(name: "publisher").delete_all # a theme from before the change
    base!("title", font: "Head", font_size: 24, text_align: "center", space_before: 40, korean_name: "제목")
    base!("subtitle", font: "Head", font_size: 16, text_align: "center", space_after: 4)
    base!("author", font: "Head", font_size: 12, text_align: "center")
    base!("body", font: "Body", font_size: 10, text_color: "CMYK=0,0,0,90", first_line_indent: 10,
                  space_before_in_lines: 1, dropcap: { "lines" => 2 })

    @big = @theme.paper_sizes.create!(size_name: "A4", width_mm: 210, height_mm: 297)
    @small = @theme.paper_sizes.create!(allow_another_size: true, size_name: "신국판", width_mm: 152, height_mm: 225)
    (%w[chapter] + KINDS).each { |t| @big.document_designs.create!(doc_type: t) }
    (%w[chapter title_page inside_cover]).each { |t| @small.document_designs.create!(doc_type: t) } # no part_cover
    # Only the rows a pre-change theme would have.
    Design::ParagraphStyle.where(styleable: @theme.document_designs).delete_all

    [ @big, @small ].each do |ps|
      ch = dd(ps, "chapter")
      row!(ch, "title", font_size: ps == @big ? 24 : 20)
      row!(ch, "subtitle", font_size: 13.5, text_align: "")         # a blank string inherits
      row!(ch, "author", font_size: 6)                               # a chapter-only override
      row!(ch, "body", font_size: 11, dropcap: { "lines" => 3 })    # dropcap skips the chapter layer
      # A sparse existing title-page row with a blank field.
      row!(dd(ps, "title_page"), "subtitle", space_after: 8, font: "")
      # inside_cover has its own publisher; title_page has none (body fallback).
      row!(dd(ps, "inside_cover"), "publisher", font_size: 9, text_align: "right")
    end
    @old = printed_by_old_code
  end

  teardown { File.delete(@theme.db_path) if File.exist?(@theme.db_path) }

  test "after the fill the new resolution prints what the old code printed, on every kind and size" do
    report = Design::HeadingStyleSeparation.call(@theme.id)
    assert_printed_unchanged
    assert report.filled.any?
    assert report.created.any?
  end

  test "the fixture's cases land as the spec says" do
    Design::HeadingStyleSeparation.call(@theme.id)
    tp = dd(@big, "title_page")

    sub = tp.paragraph_styles.find_by(name: "subtitle")
    assert_equal 8, sub.space_after.to_i, "a field already set is kept"
    assert_equal "Head", sub.font, "a blank field takes the printed value"
    assert_equal 13.5, sub.font_size.to_f, "the chapter's value is what printed"
    assert_equal "center", sub.text_align, "chapter's blank inherits the theme's"

    assert_equal 6, tp.paragraph_styles.find_by(name: "author").font_size.to_i

    pub = tp.paragraph_styles.find_by(name: "publisher")
    assert_equal "Body", pub.font, "no publisher printed body"
    assert_equal 11, pub.font_size.to_i
    assert_equal "CMYK=0,0,0,90", pub.text_color
    %w[space_before_in_lines space_after_in_lines first_line_indent dropcap korean_name].each do |f|
      assert_nil pub[f], "#{f} isn't carried from body"
    end
    assert_equal "justify", pub.text_align, "what book_write printed for a nil align, not the new theme row's centre"

    ic_pub = dd(@big, "inside_cover").paragraph_styles.find_by(name: "publisher")
    assert_equal 9, ic_pub.font_size.to_i
    assert_equal "right", ic_pub.text_align
    assert_equal @theme.base_body_font, ic_pub.font, "what book_write printed for a nil font"
  end

  test "font_size alone is marked overridden, so the generator leaves it" do
    Design::HeadingStyleSeparation.call(@theme.id)
    tp = dd(@small, "title_page")
    tp.paragraph_styles.each do |row|
      expected = row.font_size.nil? ? [] : %w[font_size]
      assert_equal expected, Array(row.overridden_fields), row.name
    end
    Design::DefaultGenerator.call(@small)
    assert_equal 20, tp.paragraph_styles.find_by(name: "title").font_size.to_i
  end

  test "the theme-level publisher row is seeded last, from body, the rest NULL" do
    Design::HeadingStyleSeparation.call(@theme.id)
    pub = @theme.base_paragraph_styles.find_by(name: "publisher")
    assert_equal [ "Body", 10, "CMYK=0,0,0,90", "center" ], [ pub.font, pub.font_size.to_i, pub.text_color, pub.text_align ]
    (Design::ParagraphStyle::STYLE_FIELDS - %w[font font_size text_color text_align]).each do |f|
      assert_nil pub[f], f
    end
  end

  test "a missing design is reported as skipped" do
    report = Design::HeadingStyleSeparation.call(@theme.id)
    assert report.skipped.any? { |s| s.include?("part_cover") && s.include?("신국판") }, report.skipped.inspect
    assert report.to_s.include?("part_cover")
  end

  test "the designs are touched" do
    before = @theme.document_designs.maximum(:updated_at)
    travel 1.minute do
      Design::HeadingStyleSeparation.call(@theme.id)
    end
    assert_operator @theme.document_designs.minimum(:updated_at), :>, before
  end

  test "it runs once: a second call is skipped and changes nothing" do
    Design::HeadingStyleSeparation.call(@theme.id)
    snapshot = rows_snapshot
    report = Design::HeadingStyleSeparation.call(@theme.id)
    assert report.skipped.any?
    assert_empty report.filled
    assert_equal snapshot, rows_snapshot
  end

  test "the fill itself is idempotent" do
    Design::HeadingStyleSeparation.call(@theme.id)
    snapshot = rows_snapshot
    @theme.base_paragraph_styles.where(name: "publisher").delete_all
    report = Design::HeadingStyleSeparation.call(@theme.id)
    assert_empty report.filled
    assert_equal snapshot.map { it.except("id") }, rows_snapshot.map { it.except("id") }
  end

  test "a normalize afterwards keeps the printed values" do
    Design::HeadingStyleSeparation.call(@theme.id)
    Design::ParagraphStyleNormalizer.compact!(@theme)
    assert_printed_unchanged
  end

  test "call_all handles every theme" do
    reports = Design::HeadingStyleSeparation.call_all
    assert_includes reports.map(&:theme_id), @theme.id
    assert_printed_unchanged
  end

  test "the .db fill gives the same rows as the records fill" do
    path = Design::ThemeDbExportService.new(@theme).export!
    copy = "#{path}.before"
    FileUtils.cp(path, copy)
    Design::HeadingStyleSeparation.call_db(copy)
    Design::HeadingStyleSeparation.call(@theme.id)
    Design::ThemeDbExportService.new(Design::Theme.find(@theme.id)).export!

    assert_equal db_styles(path), db_styles(copy)
    # Once per .db: the second run is skipped.
    assert Design::HeadingStyleSeparation.call_db(copy).skipped.any?
  ensure
    FileUtils.rm_f(copy) if copy
  end

  test "a part cover gets only its title: it never printed the other three by their aliases" do
    Design::HeadingStyleSeparation.call(@theme.id)
    rows = dd(@big, "part_cover").paragraph_styles.pluck(:name)
    assert_equal %w[title], rows
  end

  test "a pre-D5 .db's old border fields carry over from chapter" do
    path = Design::ThemeDbExportService.new(@theme).export!
    db = SQLite3::Database.new(path)
    db.execute("ALTER TABLE paragraph_styles ADD COLUMN border_thickness REAL")
    db.execute("UPDATE paragraph_styles SET border_thickness = 1.5 WHERE name = 'subtitle' AND styleable_type = 'DocumentDesign' " \
               "AND styleable_id IN (SELECT id FROM document_designs WHERE doc_type = 'chapter')")
    db.close
    Design::HeadingStyleSeparation.call_db(path)
    db = SQLite3::Database.new(path)
    values = db.execute("SELECT s.border_thickness FROM paragraph_styles s JOIN document_designs d ON d.id = s.styleable_id " \
                        "WHERE s.styleable_type = 'DocumentDesign' AND d.doc_type IN ('title_page', 'inside_cover') AND s.name = 'subtitle'").flatten
    assert_equal [ 1.5 ] * 4, values
  ensure
    db&.close
  end

  test "a .db whose theme has no body font fills book_write's literal defaults" do
    path = Design::ThemeDbExportService.new(@theme).export!
    db = SQLite3::Database.new(path)
    db.execute("UPDATE themes SET base_body_font = NULL, base_body_font_size = NULL")
    db.close
    Design::HeadingStyleSeparation.call_db(path)
    db = SQLite3::Database.new(path)
    fonts = db.execute("SELECT s.font FROM paragraph_styles s JOIN document_designs d ON d.id = s.styleable_id " \
                       "WHERE s.styleable_type = 'DocumentDesign' AND d.doc_type = 'inside_cover' AND s.name = 'publisher'").flatten
    assert_equal [ "smShinShinMyungjoP-30" ] * 2, fonts
  ensure
    db&.close
  end

  test "the .db fill uses only the columns an old .db has" do
    path = Design::ThemeDbExportService.new(@theme).export!
    db = SQLite3::Database.new(path)
    db.execute("ALTER TABLE paragraph_styles DROP COLUMN vertical_align")
    db.close
    Design::HeadingStyleSeparation.call_db(path)
    db = SQLite3::Database.new(path)
    assert_equal 1, db.get_first_value("SELECT count(*) FROM paragraph_styles WHERE styleable_type = 'Theme' AND name = 'publisher'")
  ensure
    db&.close
  end

  test "a .db from before dropcap and the D5 border fields fills title pages and the theme-level publisher" do
    path = Design::ThemeDbExportService.new(@theme).export!
    db = SQLite3::Database.new(path)
    %w[dropcap vertical_align border_top_thickness corner_top_left].each { db.execute("ALTER TABLE paragraph_styles DROP COLUMN #{it}") }
    db.close
    report = Design::HeadingStyleSeparation.call_db(path)
    assert_includes report.created, "theme-level publisher"
    db = SQLite3::Database.new(path)
    pubs = db.execute("SELECT s.font_size FROM paragraph_styles s JOIN document_designs d ON d.id = s.styleable_id " \
                      "WHERE s.styleable_type = 'DocumentDesign' AND d.doc_type = 'title_page' AND s.name = 'publisher'").flatten
    assert_equal [ 11, 11 ], pubs.map(&:to_i), "title_page's publisher falls back to body, without dropcap"
    assert_equal 1, db.get_first_value("SELECT count(*) FROM paragraph_styles WHERE styleable_type = 'Theme' AND name = 'publisher'")
  ensure
    db&.close
  end

  private

  def base!(name, **attrs) = @theme.base_paragraph_styles.create!(name: name, **attrs)

  def dd(ps, doc_type) = ps.document_designs.find_by!(doc_type: doc_type)

  # update_columns keeps blank strings (a doc-type row's save turns them into nil).
  def row!(design, name, **attrs)
    row = design.paragraph_styles.create!(name: name)
    row.update_columns(attrs)
  end

  # Render-side resolution (book_write's ThemeStyleLayers.resolve): field by
  # field, nil or blank inherits; dropcap skips the chapter layer.
  def layered(ps, doc_type, skip_chapter_for: [])
    base = @theme.base_paragraph_styles.reload.index_by(&:name).transform_values { attrs_of(it) }
    ch_dd = ps.document_designs.find_by(doc_type: "chapter")
    chapter = ch_dd ? ch_dd.paragraph_styles.reload.index_by(&:name).transform_values { attrs_of(it).merge("dropcap" => nil) } : {}
    own = dd(ps, doc_type).paragraph_styles.reload.index_by(&:name).transform_values { attrs_of(it) }
    (base.keys | chapter.keys | own.keys).to_h do |name|
      layers = [ base[name], (chapter[name] unless skip_chapter_for.include?(name)), own[name] ].compact
      next [ name, nil ] if layers.empty?
      [ name, ATTRS.index_with { |a| layers.reverse.map { it[a] }.find { !inherit?(it) } } ]
    end.compact
  end

  # The old code: theme_styles + heading_aliases (a source copied over its alias when it exists):
  # title → h1 on every kind, the other three only on HEADING_PAGE_DOC_TYPES (title_page,
  # inside_cover). A part cover carries only a title (spec §3), so only its title printed.
  def printed_by_old_code
    each_kind.to_h do |ps, kind|
      styles = layered(ps, kind)
      aliases = kind == "part_cover" ? ALIASES.slice("title") : ALIASES
      aliases.each { |src, target| styles[target] = styles[src] if styles[src] }
      [ [ ps.size_name, kind ], aliases.to_h { |name, target| [ name, styles[target] ] } ]
    end
  end

  # The new code: the four by their own names, theme → kind, the engine falling back to the old names.
  def printed_by_new_code
    each_kind.to_h do |ps, kind|
      styles = layered(ps, kind, skip_chapter_for: ALIASES.keys)
      [ [ ps.size_name, kind ], ALIASES.to_h { |name, fallback| [ name, styles[name] || styles[fallback] ] } ]
    end
  end

  def assert_printed_unchanged
    new = printed_by_new_code
    @old.each do |key, styles|
      styles.each do |name, old_attrs|
        drop = NOT_COMPARED.fetch(name, %w[korean_name])
        assert_equal rendered(old_attrs)&.except(*drop), rendered(new[key][name])&.except(*drop), "#{key.inspect} #{name}"
      end
    end
  end

  # book_write's build_style_attrs: what a nil font, size, colour or align prints as.
  def rendered(attrs)
    return unless attrs
    defaults = { "font" => @theme.base_body_font, "font_size" => @theme.base_body_font_size.to_f,
                 "text_color" => "CMYK=0,0,0,100", "text_align" => "justify" }
    attrs.merge(defaults) { |_, v, d| v.nil? ? d : v }
  end

  def each_kind
    [ @big, @small ].flat_map { |ps| KINDS.filter_map { |k| [ ps, k ] if ps.document_designs.exists?(doc_type: k) } }
  end

  def attrs_of(row) = ATTRS.index_with { |a| normalize(row[a]) }

  def normalize(v)
    v = JSON.parse(v) rescue v if v.is_a?(String) && v.start_with?("{")
    v.is_a?(Numeric) ? v.to_f : v
  end

  def inherit?(v) = v.nil? || (v.is_a?(String) && v.strip.empty?)

  def rows_snapshot
    Design::ParagraphStyle.where(styleable: @theme.document_designs).or(
      Design::ParagraphStyle.where(styleable: @theme)
    ).order(:styleable_type, :styleable_id, :name).map { it.attributes.except("updated_at", "created_at") }
  end

  def db_styles(path)
    db = SQLite3::Database.new(path)
    db.results_as_hash = true
    rows = db.execute(<<~SQL)
      SELECT ps.size_name, d.doc_type, s.* FROM paragraph_styles s
      LEFT JOIN document_designs d ON s.styleable_type = 'DocumentDesign' AND d.id = s.styleable_id
      LEFT JOIN paper_sizes ps ON ps.id = d.paper_size_id
    SQL
    rows.map { |r| [ r["size_name"], r["doc_type"], r["styleable_type"], r["name"], ATTRS.map { normalize(r[it]).then { |v| inherit?(v) ? nil : v } } ] }.sort_by(&:inspect)
  ensure
    db&.close
  end
end
