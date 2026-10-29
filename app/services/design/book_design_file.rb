module Design
  # Book designs as files (spec 2026-10-29) and the Design::Theme the studio edits. The file
  # format — the zip, its manifest, the name and language from the file name, the checks, the old
  # SQLite files told apart — is designcraft_rb's DesignCraftRb::BookDesign (Package, Name).
  # Here: a package read into a single-size theme (Loader) and a theme's size written as one
  # (Exporter).
  #
  #   theme = Design::BookDesignFile.import("클래식.book_design")       # either format
  #   Design::BookDesignFile.export(theme, to: dir)                      # => ".../클래식.book_design"
  module BookDesignFile
    class Error < StandardError; end

    module_function

    # The file (a .book_design of either format) as a Design::Theme: Loader for a package, the
    # old SQLite files (Package::Legacy) through ThemeImportService. options go to Loader
    # (name:, locale:, font_dir:).
    def import(path, **options)
      require "designcraft_rb"
      DesignCraftRb::BookDesign::Package.open(path) { Loader.new(it, **options).load! }
    rescue DesignCraftRb::BookDesign::Package::Legacy
      Design::ThemeImportService.new(path.to_s).import!
    end

    # A theme's size (default its first) written to the folder `to`; the file's path.
    def export(theme, to:, **options) = Exporter.new(theme, **options).export!(to)

    # [width, height] in mm (to 0.1) of a document.json's pages: a design's size.
    def page_size_mm(document)
      width, height = document.fetch("settings", {}).values_at("pageWidth", "pageHeight")
      raise Error, "the inner book has no page size" unless [ width, height ].all? { it.is_a?(Numeric) && it.positive? }

      [ width, height ].map { (it * 25.4 / 72).round(1) }
    end
  end
end
