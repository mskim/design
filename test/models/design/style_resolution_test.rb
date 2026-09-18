require "test_helper"

class Design::StyleResolutionTest < ActiveSupport::TestCase
  FIELDS = Design::ParagraphStyle::STYLE_FIELDS

  setup do
    @theme = Design::Theme.create!(name: "R #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @chapter  = design_for("chapter")
    @foreword = design_for("foreword")
    @base = @theme.base_paragraph_styles.create!(name: "zz_res", font: "Base Font", font_size: 10,
                                                 text_align: "left", space_after: 2)
  end

  test "chapter resolves theme base with chapter's non-nil fields on top" do
    @chapter.paragraph_styles.create!(name: "zz_res", font_size: 11)
    style = merged(@chapter, "zz_res")
    assert_equal 11, style.font_size.to_i
    assert_equal "Base Font", style.font
    assert_equal "left", style.text_align
  end

  test "a doc type with no row inherits chapter's changed field" do
    @chapter.paragraph_styles.create!(name: "zz_res", font_size: 11)
    style = merged(@foreword, "zz_res")
    assert_equal 11, style.font_size.to_i
    assert_equal "Base Font", style.font
  end

  test "a doc type row's non-nil field wins over chapter" do
    @chapter.paragraph_styles.create!(name: "zz_res", font_size: 11, text_align: "center")
    @foreword.paragraph_styles.create!(name: "zz_res", font_size: 12)
    style = merged(@foreword, "zz_res")
    assert_equal 12, style.font_size.to_i
    assert_equal "center", style.text_align
    assert_equal "Base Font", style.font
  end

  test "a style that exists only on chapter is visible to other doc types" do
    @chapter.paragraph_styles.create!(name: "zz_chapter_only", font_size: 9, font: "Ch Font")
    style = merged(@foreword, "zz_chapter_only")
    assert style, "foreword should see chapter-only style"
    assert_equal 9, style.font_size.to_i
    assert_equal "Ch Font", style.font
  end

  test "parent_values on chapter is the theme base; on foreword is chapter's resolution" do
    @chapter.paragraph_styles.create!(name: "zz_res", font_size: 11)
    @foreword.paragraph_styles.create!(name: "zz_res", font_size: 12)

    ch_parent = @chapter.parent_values("zz_res")
    assert_equal FIELDS.sort, ch_parent.keys.sort
    assert_equal 10, ch_parent["font_size"].to_i
    assert_equal "Base Font", ch_parent["font"]

    fw_parent = @foreword.parent_values("zz_res")
    assert_equal FIELDS.sort, fw_parent.keys.sort
    assert_equal 11, fw_parent["font_size"].to_i
    assert_equal "Base Font", fw_parent["font"]
    assert_equal "left", fw_parent["text_align"]
  end

  test "parity with book_write's merge_style_layers for chapter and foreword" do
    @chapter.paragraph_styles.create!(name: "zz_res", font_size: 11, text_align: "center")
    @chapter.paragraph_styles.create!(name: "zz_chapter_only", font_size: 9)
    @foreword.paragraph_styles.create!(name: "zz_res", font: "Fw Font")
    @foreword.paragraph_styles.create!(name: "zz_fw_only", space_before: 3)

    [ @chapter, @foreword ].each do |dd|
      expected = book_write_resolve(dd)
      actual = dd.merged_paragraph_styles.index_by(&:name)
      assert_equal expected.keys.sort, actual.keys.sort, "style names for #{dd.doc_type}"
      expected.each do |name, row|
        assert_equal values(row), values(actual[name]), "#{dd.doc_type} #{name}"
      end
    end
  end

  private

  def design_for(doc_type)
    @ps.document_designs.find_by(doc_type: doc_type) || @ps.document_designs.create!(doc_type: doc_type)
  end

  def merged(dd, name)
    dd.merged_paragraph_styles.find { |s| s.name == name }
  end

  def values(row) = FIELDS.index_with { |f| row[f] }

  # Port of book_write PdfGenerationService#merged_styles_for / #merge_style_layers
  # (app/services/pdf_generation_service.rb), operating on AR rows instead of Sequel hashes.
  def book_write_resolve(dd)
    base_styles = @theme.base_paragraph_styles.reload.index_by(&:name)
    chapter_dd = dd.paper_size.document_designs.find_by(doc_type: "chapter")
    chapter_overrides = chapter_dd ? chapter_dd.paragraph_styles.reload.index_by(&:name) : {}
    chapter_resolved = merge_style_layers(base_styles, chapter_overrides)
    return chapter_resolved.compact if dd.doc_type == "chapter"

    merge_style_layers(chapter_resolved, dd.paragraph_styles.reload.index_by(&:name)).compact
  end

  def merge_style_layers(base_by_name, overrides_by_name)
    (base_by_name.keys + overrides_by_name.keys).uniq.each_with_object({}) do |name, result|
      base = base_by_name[name]
      override = overrides_by_name[name]
      result[name] = if override && base
        merged = override.dup
        Design::DocumentDesign::MERGEABLE_ATTRS.each { |attr| merged[attr] = base[attr] if override[attr].nil? }
        merged
      elsif override
        override
      else
        base
      end
    end
  end
end
