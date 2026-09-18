module Design
  # Shared PDF→JPG rendering (ruby-vips). Reads the PDF as a buffer to bypass
  # Vips file-path caching, flattens any alpha to white, JPEG-encodes at Q 85.
  class PdfToJpg
    JPEG_QUALITY = 85

    def self.convert(pdf_path, jpg_path, dpi: 150)
      pdf_data = File.binread(pdf_path)
      image = Vips::Image.new_from_buffer(pdf_data, "", dpi: dpi, access: :sequential)
      flatten(image).jpegsave(jpg_path, Q: JPEG_QUALITY)
      jpg_path
    end

    # Rasterize pages 1..[n_pages, max_pages].min into <dir>/preview_<n>.jpg.
    # One pdfload with n: -1 yields a vertical strip of all pages; vips exposes
    # the per-page height and page count as image metadata, so each page is a crop.
    # Returns the number of pages written.
    def self.convert_pages(pdf_path, dir, max_pages: 4, dpi: 150)
      pdf_data = File.binread(pdf_path)
      strip = Vips::Image.new_from_buffer(pdf_data, "", dpi: dpi, n: -1)
      # libvips only sets page-height when there is more than one page (verified on 8.17.3);
      # a single page IS the strip. n-pages is always present.
      page_height = strip.get_fields.include?("page-height") ? strip.get("page-height") : strip.height
      count = [ strip.get("n-pages"), max_pages ].min
      count.times do |i|
        page = strip.extract_area(0, i * page_height, strip.width, page_height)
        flatten(page).jpegsave(File.join(dir, "preview_#{i + 1}.jpg"), Q: JPEG_QUALITY)
      end
      count
    end

    def self.flatten(image)
      image.bands == 4 ? image.flatten(background: [ 255, 255, 255 ]) : image
    end
    private_class_method :flatten
  end
end
