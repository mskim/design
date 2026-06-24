require "hexapdf"
require "doc_processor_rb/core/layout/inline_table"

module Design
  class SingleTablePdf
    def self.write(path, rows:, style_hash:, page_width: 595.28, page_height: 200.0)
      new(path: path, rows: rows, style_hash: style_hash,
          page_width: page_width, page_height: page_height).write
    end

    def initialize(path:, rows:, style_hash:, page_width:, page_height:)
      @path = path
      @rows = rows
      @style_hash = style_hash
      @page_width = page_width
      @page_height = page_height
    end

    def write
      doc = HexaPDF::Document.new
      page = doc.pages.add([ 0, 0, @page_width, @page_height ])
      canvas = page.canvas

      table_width = @page_width - 60
      table = DocProcessorRb::Layout::InlineTable.new(
        rows: @rows,
        width: table_width,
        style_hash: @style_hash
      )
      table.measure
      table.draw_pdf(canvas, x: 30, y: @page_height - 30)

      doc.write(@path)
      @path
    end
  end
end
