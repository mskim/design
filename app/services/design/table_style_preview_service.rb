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
        designcraft_table(pdf_file.path, style_hash) ||
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

    private

    # The sample table as DesignCraft lays the book's tables out (Design.config.designcraft):
    # one table in a unit the size of SingleTablePdf's page, in the theme's table style; the
    # theme's body font for cells whose style names none. Nil when DesignCraft isn't on or
    # fails (logged): SingleTablePdf draws it.
    def designcraft_table(path, style_hash)
      return unless Design.designcraft?

      require "designcraft_rb"
      body = { font_family: @theme.base_body_font, font_size: @theme.base_body_font_size }.compact
      spec = { version: 1, type: "chapter",
               page: { width: 595.28, height: 200.0, margins: { top: 30, bottom: 30, inside: 30, outside: 30 }, line_height: 14 },
               styles: (body.empty? ? {} : { body: body }),
               blocks: [ { type: "table", rows: Design::TableStylePreviewSample::SAMPLE[:rows], style_hash: style_hash } ] }
      DesignCraftRb.render(JSON.parse(spec.to_json), pdf: path)
      path
    rescue StandardError, LoadError => e
      Rails.logger.error "Design::TableStylePreviewService DesignCraft failed; SingleTablePdf draws it: #{e.class}: #{e.message}"
      nil
    end
  end
end
