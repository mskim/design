require "test_helper"
require "rake"

class Design::ParagraphStyleNormalizerTest < ActiveSupport::TestCase
  FIELDS = Design::ParagraphStyle::STYLE_FIELDS

  setup do
    @theme = Design::Theme.create!(name: "Norm #{SecureRandom.hex(3)}", locale: "ko")
    @ps1 = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @ps2 = @theme.paper_sizes.create!(size_name: "국판", width_mm: 148, height_mm: 210)
    @chapters  = [ @ps1, @ps2 ].map { |ps| design_for(ps, "chapter") }
    @forewords = [ @ps1, @ps2 ].map { |ps| design_for(ps, "foreword") }

    @base = @theme.base_paragraph_styles.create!(name: "zz_body", font: "Base Font", font_size: 10,
                                                 text_align: "left", space_before: 2)
    @quote = @theme.base_paragraph_styles.create!(name: "zz_quote", font: "Quote Font", font_size: 9)

    # Old-style full snapshots, written with update_columns to bypass the
    # doc-type callbacks (blank→nil, nil-on-create).
    @chapters.each do |dd|
      snapshot!(dd, "zz_body", @base, font_size: 11, text_color: "", overridden_fields: %w[font_size font])
      snapshot!(dd, "zz_quote", @quote)
    end
    @forewords.each do |dd|
      # A snapshot of chapter's resolution (font_size 11), plus its own text_align.
      snapshot!(dd, "zz_body", @base, font_size: 11, text_align: "right", tracking: "",
                overridden_fields: %w[font_size text_align])
      snapshot!(dd, "zz_quote", @quote)
      # Parentless styles (no base, no chapter row).
      snapshot!(dd, "zz_orphan", nil, font_size: 8)
      snapshot!(dd, "zz_empty_orphan", nil, font: "")
    end
  end

  teardown do
    File.delete(db_path) if File.exist?(db_path)
  end

  test "values equal to the parent become nil, blanks become nil, differing values stay" do
    normalize!

    @chapters.each do |dd|
      row = row_of(dd, "zz_body")
      assert_equal 11, row.font_size.to_i
      assert_nil row.font, "equal to the theme base"
      assert_nil row.text_align
      assert_nil row.space_before
      assert_nil row.scale
      assert_nil row.text_color, "\"\" becomes nil"
    end
    @forewords.each do |dd|
      row = row_of(dd, "zz_body")
      assert_equal "right", row.text_align
      assert_nil row.tracking, "\"\" becomes nil"
      assert_nil row.font
      assert_nil row.text_color
      assert_equal [ "text_align" ], FIELDS.reject { |f| row[f].nil? }
    end
  end

  test "chapter is normalised first: a foreword value equal to chapter's becomes nil even when it differs from the theme" do
    normalize!

    @forewords.each do |dd|
      row = row_of(dd, "zz_body")
      assert_nil row.font_size
      # Chapter's "" text_color is cleared first, so foreword's copy of the theme
      # value now equals its parent (compared against the raw "" it would stay).
      assert_nil row.text_color
    end
  end

  test "rows left empty with a parent are deleted; parentless rows are kept" do
    normalize!

    (@chapters + @forewords).each { |dd| assert_nil row_of(dd, "zz_quote") }
    @forewords.each do |dd|
      assert_equal 8, row_of(dd, "zz_orphan").font_size.to_i
      empty = row_of(dd, "zz_empty_orphan")
      assert empty, "a parentless row is kept even when empty"
      assert FIELDS.all? { |f| empty[f].nil? }
    end
  end

  test "overridden_fields only loses fields that became nil" do
    normalize!

    @chapters.each { |dd| assert_equal [ "font_size" ], row_of(dd, "zz_body").overridden_fields }
    @forewords.each { |dd| assert_equal [ "text_align" ], row_of(dd, "zz_body").overridden_fields }
  end

  test "resolved STYLE_FIELDS are identical before and after, except fields that were blank" do
    designs = @theme.document_designs.to_a
    before = designs.to_h { |dd| [ dd.id, resolved(dd) ] }

    normalize!

    compared = 0
    designs.each do |dd|
      after = resolved(dd.reload)
      assert_equal before[dd.id].keys.sort, after.keys.sort, "#{dd.doc_type}: style names"
      before[dd.id].each do |name, values|
        kept = values.reject { |_f, v| v.is_a?(String) && v.strip.empty? }
        assert_equal kept, after[name].slice(*kept.keys), "#{dd.doc_type}/#{dd.paper_size.size_name} #{name}"
        compared += kept.size
      end
    end
    assert_operator compared, :>, 0
  end

  test "touches every design of the theme" do
    past = 1.day.ago
    @theme.document_designs.update_all(updated_at: past)

    normalize!

    @theme.document_designs.reload.each { |dd| assert_operator dd.updated_at, :>, past + 1.hour }
  end

  test "re-exports the theme .db" do
    File.delete(db_path) if File.exist?(db_path)

    normalize!

    assert File.exist?(db_path), "expected #{db_path}"
    db = SQLite3::Database.new(db_path)
    rows = db.execute(<<~SQL, @forewords.map(&:id))
      SELECT font_size, text_align FROM paragraph_styles
      WHERE styleable_type = 'DocumentDesign' AND name = 'zz_body' AND styleable_id IN (?, ?)
    SQL
    db.close
    assert_equal [ [ nil, "right" ], [ nil, "right" ] ], rows, "the export carries the normalised rows"
  end

  test "compact! compacts the rows but does not export (for use inside a transaction)" do
    File.delete(db_path) if File.exist?(db_path)

    Design::ParagraphStyleNormalizer.compact!(@theme)

    assert_nil @forewords.first.paragraph_styles.find_by(name: "zz_body").font_size
    refute File.exist?(db_path), "compact! must leave the export to the caller"
  end

  test "design:normalize_paragraph_styles rake task is defined" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("design:normalize_paragraph_styles")
    assert Rake::Task.task_defined?("design:normalize_paragraph_styles")
  end

  private

  def normalize! = Design::ParagraphStyleNormalizer.call(@theme)

  def design_for(ps, doc_type)
    ps.document_designs.find_by(doc_type: doc_type) || ps.document_designs.create!(doc_type: doc_type)
  end

  def row_of(dd, name) = dd.paragraph_styles.find_by(name: name)

  # Full-snapshot row: every STYLE_FIELD copied from `source` (nil when none),
  # then `overrides`, written with update_columns.
  def snapshot!(dd, name, source, **overrides)
    row = dd.paragraph_styles.find_or_create_by!(name: name)
    values = FIELDS.index_with { |f| source&.[](f) }
    row.update_columns(values.merge(overrides.transform_keys(&:to_s)))
    row
  end

  def resolved(dd)
    dd.merged_paragraph_styles.to_h { |s| [ s.name, FIELDS.index_with { |f| s[f] } ] }
  end

  def db_path = File.join(Design.themes_dir, "#{@theme.file_basename}.db")
end
