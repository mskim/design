require "tempfile"

module Design
  class TableStylePreviewService
    PREVIEW_DPI = 150

    def self.call(theme, table_style)
      new(theme, table_style).call
    end

    def initialize(theme, table_style)
      @theme = theme
      @table_style = table_style
    end

    def call
      style_hash = Design::TableStyleResolver.call(@theme, @table_style)

      pdf_file = Tempfile.new(%w[ts_preview .pdf])
      jpg_file = Tempfile.new(%w[ts_preview .jpg])
      begin
        Design::SingleTablePdf.write(
          pdf_file.path,
          rows: Design::TableStylePreviewSample::SAMPLE[:rows],
          style_hash: style_hash
        )
        Design::PdfToJpg.convert(pdf_file.path, jpg_file.path, dpi: PREVIEW_DPI)
        File.binread(jpg_file.path)
      ensure
        pdf_file.close!
        jpg_file.close!
      end
    end
  end
end
