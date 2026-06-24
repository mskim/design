module Design
  # Shared PDF→JPG rendering (ruby-vips). Reads the PDF as a buffer to bypass
  # Vips file-path caching, flattens any alpha to white, JPEG-encodes at Q 85.
  class PdfToJpg
    def self.convert(pdf_path, jpg_path, dpi: 150)
      pdf_data = File.binread(pdf_path)
      image = Vips::Image.new_from_buffer(pdf_data, "", dpi: dpi, access: :sequential)
      image = image.flatten(background: [ 255, 255, 255 ]) if image.bands == 4
      image.jpegsave(jpg_path, Q: 85)
      jpg_path
    end
  end
end
