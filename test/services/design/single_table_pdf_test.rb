require "test_helper"
require "tempfile"

class Design::SingleTablePdfTest < ActiveSupport::TestCase
  test "writes a non-empty single-page table PDF from the sample rows" do
    theme = Design::Theme.create!(name: "STP #{SecureRandom.hex(3)}", locale: "ko")
    style_hash = Design::TableStyleResolver.call(theme, theme.table_styles.find_by(name: "grid"))
    pdf = Tempfile.new(%w[stp .pdf])
    begin
      out = Design::SingleTablePdf.write(pdf.path,
        rows: Design::TableStylePreviewSample::SAMPLE[:rows], style_hash: style_hash)
      assert_equal pdf.path, out
      assert File.size(pdf.path) > 500, "pdf looks empty"
      assert_equal "%PDF", File.binread(pdf.path, 4)
    ensure
      pdf.close!
    end
  end

  test "the sample has one header row and three body rows" do
    rows = Design::TableStylePreviewSample::SAMPLE[:rows]
    assert_equal 1, rows.count { |r| r[:kind] == :header }
    assert_equal 3, rows.count { |r| r[:kind] == :body }
  end
end
