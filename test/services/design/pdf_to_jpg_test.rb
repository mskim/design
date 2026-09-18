require "test_helper"
require "hexapdf"
require "tempfile"
require "tmpdir"

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

  # Builds an N-page PDF with HexaPDF; each page gets a filled square so the JPEGs are non-trivial.
  def multi_page_pdf(pages)
    pdf = Tempfile.new(%w[p2j-multi .pdf])
    doc = HexaPDF::Document.new
    pages.times { doc.pages.add([ 0, 0, 200, 100 ]).canvas.tap { |c| c.rectangle(10, 10, 50, 50).fill } }
    doc.write(pdf.path)
    pdf
  end

  test "convert_pages writes one JPEG per page and returns the count" do
    pdf = multi_page_pdf(3)
    Dir.mktmpdir do |dir|
      count = Design::PdfToJpg.convert_pages(pdf.path, dir, dpi: 72)
      assert_equal 3, count
      assert_equal %w[preview_1.jpg preview_2.jpg preview_3.jpg], Dir.children(dir).sort
      assert File.size(File.join(dir, "preview_3.jpg")) > 500
    end
  ensure
    pdf&.close!
  end

  test "convert_pages honours max_pages" do
    pdf = multi_page_pdf(3)
    Dir.mktmpdir do |dir|
      assert_equal 2, Design::PdfToJpg.convert_pages(pdf.path, dir, max_pages: 2, dpi: 72)
      assert_equal %w[preview_1.jpg preview_2.jpg], Dir.children(dir).sort
    end
  ensure
    pdf&.close!
  end

  test "convert_pages on a single-page PDF returns 1" do
    pdf = multi_page_pdf(1)
    Dir.mktmpdir do |dir|
      assert_equal 1, Design::PdfToJpg.convert_pages(pdf.path, dir, dpi: 72)
    end
  ensure
    pdf&.close!
  end
end
