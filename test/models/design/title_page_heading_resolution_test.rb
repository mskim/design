require "test_helper"

# title, subtitle, author and publisher on the title-page kinds (title_page,
# inside_cover, part_cover) resolve theme → that kind: the chapter layer is
# skipped for them, and only for them (spec 2026-10-26 §5).
class Design::TitlePageHeadingResolutionTest < ActiveSupport::TestCase
  setup do
    @theme = Design::Theme.create!(name: "TP #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @chapter = design_for("chapter")
    @title_page = design_for("title_page")
    @foreword = design_for("foreword")
    %w[inside_cover part_cover thanks].each { design_for(it) }
    # Start from bare layers: no generator rows anywhere.
    Design::ParagraphStyle.where(styleable: @theme.document_designs).delete_all
    @theme.base_paragraph_styles.create!(name: "subtitle", font: "Base", font_size: 16, text_align: "center")
    @theme.base_paragraph_styles.create!(name: "body", font: "Body", font_size: 10)
    @chapter.paragraph_styles.create!(name: "subtitle", font_size: 13.5, space_after: 4)
    @chapter.paragraph_styles.create!(name: "body", font_size: 11)
  end

  test "the TITLE_PAGE_KINDS and HEADING_NAMES" do
    assert_equal %w[title_page inside_cover part_cover], Design::DocumentDesign::TITLE_PAGE_KINDS
    assert_equal %w[title subtitle author publisher], Design::DocumentDesign::HEADING_NAMES
  end

  test "merged_paragraph_styles skips chapter for a heading name on every title-page kind" do
    Design::DocumentDesign::TITLE_PAGE_KINDS.each do |kind|
      dd = design_for(kind)
      sub = merged(dd, "subtitle")
      assert_equal 16, sub.font_size.to_i, kind
      assert_nil sub.space_after, kind
    end
  end

  test "a heading name defined only on chapter isn't visible on a title-page kind" do
    @chapter.paragraph_styles.create!(name: "author", font_size: 6)
    assert_nil merged(@title_page, "author")
    assert_not @title_page.style_exists?("author")
  end

  test "body on a title-page kind and subtitle on a chapter-like kind still go through chapter" do
    assert_equal 11, merged(@title_page, "body").font_size.to_i
    assert_equal 13.5, merged(@foreword, "subtitle").font_size.to_f
    assert_equal 4, merged(@foreword, "subtitle").space_after.to_i
    assert_equal 13.5, merged(design_for("thanks"), "subtitle").font_size.to_f
  end

  test "parent_values, style_state and style_has_parent? use the theme alone" do
    assert_equal 16, @title_page.parent_values("subtitle")["font_size"].to_i
    assert_nil @title_page.parent_values("subtitle")["space_after"]
    assert_equal 11, @title_page.parent_values("body")["font_size"].to_i
    assert_equal 13.5, @foreword.parent_values("subtitle")["font_size"].to_f

    @chapter.paragraph_styles.create!(name: "author", font_size: 6)
    assert_not @title_page.style_has_parent?("author")
    assert_not @title_page.style_state("author")[:has_parent]
    assert @foreword.style_has_parent?("author")
  end

  test "an edit equal to the theme value reverts it, one equal to chapter's is stored" do
    @title_page.set_style_field!("subtitle", "font_size", 13.5)
    assert_equal 13.5, @title_page.paragraph_styles.find_by(name: "subtitle").font_size.to_f
    @title_page.set_style_field!("subtitle", "font_size", 16)
    assert_nil @title_page.paragraph_styles.find_by(name: "subtitle")
  end

  test "a push of a heading name from a title-page kind goes to the theme, not chapter" do
    @title_page.set_style_field!("subtitle", "font_size", 20)
    @title_page.set_style_field!("subtitle", "dropcap", { "lines" => 3 })
    assert_includes @title_page.pushable_fields("subtitle"), "dropcap"
    @title_page.reload.push_style!("subtitle")

    assert_equal 20, @theme.base_paragraph_styles.find_by(name: "subtitle").font_size.to_i
    assert_equal 13.5, @chapter.paragraph_styles.find_by(name: "subtitle").font_size.to_f
    assert_nil @title_page.paragraph_styles.find_by(name: "subtitle")
  end

  test "a push from a title-page kind needs no chapter design" do
    @chapter.destroy!
    dd = @title_page.reload
    dd.set_style_field!("subtitle", "font_size", 20)
    dd.reload.push_style!("subtitle")
    assert_equal 20, @theme.base_paragraph_styles.find_by(name: "subtitle").font_size.to_i
  end

  test "a push of body from a title-page kind still goes to chapter" do
    @title_page.set_style_field!("body", "font_size", 12)
    @title_page.reload.push_style!("body")
    assert_equal 12, @chapter.paragraph_styles.find_by(name: "body").font_size.to_i
    assert_equal 10, @theme.base_paragraph_styles.find_by(name: "body").font_size.to_i
  end

  test "the normalizer compares a title-page heading row with the theme alone" do
    # Equal to chapter (kept), equal to the theme (cleared).
    @title_page.paragraph_styles.create!(name: "subtitle", font_size: 13.5, text_align: "center")
    Design::ParagraphStyleNormalizer.compact!(@theme)
    row = @title_page.paragraph_styles.find_by(name: "subtitle")
    assert_equal 13.5, row.font_size.to_f
    assert_nil row.text_align

    # body on the title page still compares with chapter.
    @title_page.paragraph_styles.create!(name: "body", font_size: 11)
    Design::ParagraphStyleNormalizer.compact!(@theme)
    assert_nil @title_page.paragraph_styles.find_by(name: "body")
  end

  test "the normalizer keeps a title-page row whose style only chapter also has" do
    @chapter.paragraph_styles.create!(name: "author", font_size: 6)
    @title_page.paragraph_styles.create!(name: "author", font_size: 6)
    Design::ParagraphStyleNormalizer.compact!(@theme)
    assert_equal 6, @title_page.paragraph_styles.find_by(name: "author").font_size.to_i
  end

  private

  def design_for(doc_type)
    @ps.document_designs.find_by(doc_type: doc_type) || @ps.document_designs.create!(doc_type: doc_type)
  end

  def merged(dd, name) = dd.merged_paragraph_styles.find { |s| s.name == name }
end
