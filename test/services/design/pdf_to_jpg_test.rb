require "test_helper"
require "hexapdf"
require "tempfile"

class Design::PdfToJpgTest < ActiveSupport::TestCase
  test "converts a PDF file into a non-empty JPEG file" do
    pdf = Tempfile.new(%w[p2j .pdf])
    jpg = Tempfile.new(%w[p2j .jpg])
    begin
      doc = HexaPDF::Document.new
      doc.pages.add([ 0, 0, 200, 100 ]).canvas.tap { |c| c.rectangle(10, 10, 50, 50).fill }
      doc.write(pdf.path)

      out = Design::PdfToJpg.convert(pdf.path, jpg.path, dpi: 72)

      assert_equal jpg.path, out
      assert File.exist?(jpg.path)
      assert File.size(jpg.path) > 500, "jpeg looks empty"
    ensure
      pdf.close!
      jpg.close!
    end
  end
end
