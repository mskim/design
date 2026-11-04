require "tmpdir"

module Design
  module BookDesignFile
    # A theme's size written as a .book_design (spec 2026-10-29): each doc type's sample laid
    # out by DesignCraft, as the studio previews it and book_design's DesignCraftSampleService
    # saves it (the preview's unit as DesignCraftRb::UnitRows → a document), the samples joined
    # into one inner_page.designcraft in reading order (DesignCraftRb.export_merged), each doc
    # type's pages in the manifest. The cover panels make book_cover.designcraft, one spread as
    # the studio's cover previews lay them out (DesignCraftRb::DocProcessor::Cover). The package
    # is written and checked by DesignCraftRb::BookDesign::Package.write.
    #
    # The manifest's `theme` carries the theme's rows for this one size (theme, base styles,
    # paper size, document designs with their heading elements and styles, table styles): what
    # the documents can't say. Its `styles` map is the identity: the documents' paragraph styles
    # are named after the app's.
    #
    # The file is named after the theme ("#{theme.name}.book_design"), so the name round-trips;
    # the locale does when the name implies it (a Korean theme named in Latin letters reads as
    # English: Loader takes locale: for that, and #locale_from_name? tells).
    #
    # Needs designcraft_rb and designcraft-cli (DESIGNCRAFT_CLI, or on the PATH).
    class Exporter
      class Unavailable < Error; end

      # What designcraft_rb lays out as a unit (DesignCraftSampleService::DOC_TYPES): not the
      # cover panels, the document cover or a blank page.
      DOC_TYPES = (Design::DocumentDesign::BODY_FLOW_DOC_TYPES +
                   %w[poem title_page inside_cover part_cover thanks dedication toc copyright]).freeze
      THEME_FIELDS = %w[name locale base_body_font base_body_font_size base_heading_font description].freeze
      GENERATOR = "design #{Design::VERSION}".freeze
      INNER_PAGE = "inner_page.designcraft"
      BOOK_COVER = "book_cover.designcraft"

      attr_reader :theme, :paper_size

      # paper_size: the size to write (default the theme's first). cover: false leaves
      # book_cover.designcraft out.
      def initialize(theme, paper_size: nil, cover: true)
        @theme = theme
        @paper_size = paper_size || theme.default_paper_size or raise ArgumentError, "#{theme.name} has no paper size"
        @cover = cover
      end

      # The theme's name, less what a file name can't hold (Name.of refuses it).
      def design_name = theme.name.to_s.gsub(%r{[/\\\x00-\x1f]}, "-").strip.presence || theme.file_basename

      def file_name = "#{design_name}.book_design"

      # Whether the file name gives the theme's locale back (its language is the name's).
      def locale_from_name?
        require_designcraft!
        DesignCraftRb::BookDesign::Name.of(design_name).locale == theme.locale
      end

      # Writes dir/#file_name; returns its path.
      def export!(dir)
        require_designcraft!
        Dir.mktmpdir("book_design") do |work|
          inner = doc_types = cover = nil
          DesignCraftRb::Client.open do |client|
            inner, doc_types = write_inner_page(client, work)
            cover = write_book_cover(client, work) if @cover
          end
          DesignCraftRb::BookDesign::Package.write(name: design_name, inner_page: inner, book_cover: cover&.first, to: dir,
                                                   manifest: manifest(inner, doc_types, cover&.last))
        end
      end

      # The theme's rows for this size, as JSON values (Loader#apply_theme reads them back).
      def theme_attributes
        designs = paper_size.document_designs.includes(:heading_elements, :paragraph_styles).order(:id)
        {
          "theme" => theme.attributes.slice(*THEME_FIELDS),
          "paragraph_styles" => theme.base_paragraph_styles.order(:id).map { row(it) },
          "paper_size" => row(paper_size),
          "document_designs" => designs.map do |design|
            row(design).merge("heading_elements" => design.heading_elements.map { row(it) },
                              "paragraph_styles" => design.paragraph_styles.sort_by(&:id).map { row(it) })
          end,
          "table_styles" => theme.table_styles.order(:id).map { row(it) }
        }
      end

      private

      def require_designcraft!
        require "designcraft_rb"
        DesignCraftRb::BookDesign::Package
      rescue LoadError, NameError => e
        raise Unavailable, "exporting a .book_design needs designcraft_rb with BookDesign (#{e.message})"
      end

      # Each doc type's sample laid out and saved, then joined: [path, {doc_type => pages}].
      # A package must have a chapter (the body flow every other doc type is read against).
      def write_inner_page(client, work)
        designs = Design::DocumentDesign.by_reading_order(paper_size.document_designs.where(doc_type: DOC_TYPES).to_a)
        raise ArgumentError, "#{theme.name}: a .book_design needs a chapter design" unless designs.any? { it.doc_type == "chapter" }

        first = 0
        units = designs.each_with_index.map do |design, index|
          unit = File.join(work, "#{index}_#{design.doc_type}.designcraft")
          count = lay_out(client, design, work, unit)
          range = { "first_page" => first, "page_count" => count }
          first += count
          [ unit, design.doc_type, range ]
        end
        path = File.join(work, INNER_PAGE)
        kinds = units.map { it[1] }
        DesignCraftRb.export_merged(units.map(&:first), designcraft: path, title: theme.name, labels: kinds, kinds: kinds,
                                    client: client)
        [ path, units.to_h { [ it[1], it[2] ] } ]
      end

      # One sample saved as a .designcraft; its page count.
      def lay_out(client, design, work, path)
        rows = Sample.new(design, paper_size: paper_size, work_dir: work).rows
        document = rows.to_spec(base_dir: work).unit.to_document(font_dir: DesignCraftRb.font_dir, start_page: 1)
        document.build(client, preflight: false)
        client.tool(:save_document, path: path)
        client.tool(:inspect_document)["pageCount"].to_i.tap { client.execute("file.close") }
      end

      # The cover panels as one spread: [path, the manifest's cover], or nil without panels.
      def write_book_cover(client, work)
        designs = paper_size.document_designs.where(doc_type: Design::DocumentDesign::COVER_PANEL_TYPES).to_a
        return if designs.empty?

        mm = Design::PaperSize::MM2PT
        spine, flap = Design::PreviewService::COVER_SPINE_MM, Design::PreviewService::WING_FLAP_WIDTH_MM
        wings = designs.any? { Design::DocumentDesign::WING_PANEL_TYPES.include?(it.doc_type) }
        panels = designs.to_h { [ it.doc_type, Sample.new(it, paper_size: paper_size, work_dir: work).rows.rows ] }
        cover = DesignCraftRb::DocProcessor::Cover.new(width: paper_size.width_pt, height: paper_size.height_pt,
                                                       spine: spine * mm, flap: (flap * mm if wings), panels: panels, title: theme.name)
        path = File.join(work, BOOK_COVER)
        cover.build(client).export(client, designcraft: path)
        client.execute("file.close")
        [ path, { "spine_mm" => spine, "flap_mm" => (flap if wings),
                  "panels" => cover.types.each_with_index.to_h { |type, i| [ type, { "first_page" => i, "page_count" => 1 } ] } }.compact ]
      end

      def manifest(inner, doc_types, cover)
        { "generator" => GENERATOR, "doc_types" => doc_types, "styles" => style_roles(inner), "cover" => cover,
          "theme" => theme_attributes }.compact
      end

      # The theme's style names the joined document has (as the chapter defines them): role →
      # itself.
      def style_roles(inner)
        document = JSON.parse(DesignCraftRb::ZipFile.read(inner).fetch("document.json"))
        names = Array(document.dig("styles", "paragraph")).map { it["name"] }
        chapter = paper_size.document_designs.find_by(doc_type: "chapter")
        roles = theme.base_paragraph_styles.pluck(:name) | Array(chapter&.paragraph_styles&.pluck(:name))
        (roles & names).sort.index_with(&:itself)
      end

      # A record's fields as JSON values, less ids, ownership and timestamps.
      def row(record)
        record.attributes.except(*Loader::SKIPPED).transform_values { json_value(it) }
      end

      def json_value(value)
        case value
        when BigDecimal then value.to_f
        when Time, DateTime, Date then value.iso8601
        else value
        end
      end

      # A design's preview unit, written for a document instead of a preview image (the sample
      # wing covers go to the export's work folder).
      class Sample < Design::PreviewService
        def initialize(document_design, paper_size:, work_dir:)
          super(document_design, paper_size: paper_size)
          @work_dir = work_dir
        end

        def rows = DesignCraftRb::UnitRows.new.tap { populate_database(it) }
      end
    end
  end
end
