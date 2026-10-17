require "test_helper"

# Decision 4: dropcap resolves theme base → doc type; the chapter layer is skipped.
class Design::DocumentDesignDropcapTest < ActiveSupport::TestCase
  CAP = { "lines" => 3, "chars" => 1 }.freeze
  OFF = { "enabled" => false }.freeze

  setup do
    @theme = Design::Theme.create!(name: "DCI #{SecureRandom.hex(3)}", locale: "ko")
    @ps = @theme.paper_sizes.create!(size_name: "신국판", width_mm: 152, height_mm: 225)
    @chapter  = design_for("chapter")
    @foreword = design_for("foreword")
    @base = @theme.base_paragraph_styles.create!(name: "zz_body", font: "Base Font", font_size: 10)
  end

  test "a cap on chapter does not reach a doc type with no row of its own" do
    @chapter.paragraph_styles.create!(name: "zz_body", font_size: 11, dropcap: CAP)

    fw = merged(@foreword, "zz_body")
    assert_nil fw.dropcap
    assert_equal 11, fw.font_size.to_i, "other fields still come from chapter"
    assert_nil @foreword.parent_values("zz_body")["dropcap"]
    assert_equal 11, @foreword.parent_values("zz_body")["font_size"].to_i
    assert_equal CAP, merged(@chapter, "zz_body").dropcap
  end

  test "a cap on a chapter-only style does not reach other doc types" do
    @chapter.paragraph_styles.create!(name: "zz_chapter_only", font: "Ch Font", dropcap: CAP)

    fw = merged(@foreword, "zz_chapter_only")
    assert_nil fw.dropcap
    assert_equal "Ch Font", fw.font
  end

  test "a cap on the theme base reaches the doc type; the doc type can switch it off" do
    @base.update!(dropcap: CAP)
    @chapter.paragraph_styles.create!(name: "zz_body", dropcap: OFF)

    assert_equal CAP, merged(@foreword, "zz_body").dropcap
    assert_equal CAP, @foreword.parent_values("zz_body")["dropcap"]

    @foreword.set_style_field!("zz_body", "dropcap", { "enabled" => false })
    row = @foreword.paragraph_styles.find_by(name: "zz_body")
    assert_equal OFF, row&.dropcap, "off differs from the theme base cap: stored, not reverted"
    assert_equal OFF, merged(@foreword, "zz_body").dropcap
  end

  test "merging leaves chapter's row untouched" do
    ch_row = @chapter.paragraph_styles.create!(name: "zz_body", dropcap: CAP)
    @foreword.merged_paragraph_styles
    @foreword.parent_values("zz_body")

    assert_equal CAP, ch_row.dropcap
    refute ch_row.changed?
    assert_equal CAP, ch_row.reload.dropcap
  end

  test "push_preview and push_style! from a doc type leave dropcap out" do
    @foreword.set_style_field!("zz_body", "font_size", 12)
    @foreword.set_style_field!("zz_body", "dropcap", CAP)

    assert_equal [ "font_size" ], @foreword.push_preview("zz_body").keys

    @foreword.push_style!("zz_body")
    ch_row = @chapter.paragraph_styles.find_by(name: "zz_body")
    assert_equal 12, ch_row.font_size.to_i
    assert_nil ch_row.dropcap
    fw_row = @foreword.paragraph_styles.find_by(name: "zz_body")
    assert_equal CAP, fw_row&.dropcap, "the doc type keeps its own cap"
    assert_nil fw_row.font_size
  end

  test "push_style! from chapter still moves dropcap to the theme base" do
    @chapter.set_style_field!("zz_body", "dropcap", CAP)

    assert_includes @chapter.push_preview("zz_body").keys, "dropcap"
    @chapter.push_style!("zz_body")
    assert_equal CAP, @base.reload.dropcap
  end

  private

  def design_for(doc_type)
    @ps.document_designs.find_by(doc_type: doc_type) || @ps.document_designs.create!(doc_type: doc_type)
  end

  def merged(dd, name) = dd.merged_paragraph_styles.find { |s| s.name == name }
end
