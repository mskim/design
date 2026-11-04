module Design
  module BookDesignFile
    # A .book_design package (DesignCraftRb::BookDesign::Package, open) read into a single-size
    # Design::Theme, the model the studio edits and renders read (spec 2026-10-29). Name and
    # locale are the package's (its file name's) unless name:/locale: are given; the size is the
    # inner book's pages'.
    #
    # With the exporter's `theme` in the manifest, the theme's rows are applied as
    # ThemeImportService imports a SQLite file: base styles, the size, its document designs
    # with their heading elements and styles, table styles. Without it (an IDML or
    # .designcraft import), the theme is derived from the inner book: margins from the
    # parent page of the chapter's pages (or the first body page), body lines from the text
    # area over the body's leading, base styles from the book's styles mapped to roles
    # (manifest `styles`), every doc type from the defaults (PaperSizeSeeder).
    #
    # Either way it ends as an import does: default table and cell styles seeded, doc-type
    # rows compacted, the theme's .db exported. A system theme of the same name (NFC) and
    # locale is updated in place, keeping its id, which books' design_theme_<id> refer to; for
    # an all-ASCII name, the same parameterized name too (an imported "classic" becomes
    # "Classic"). parameterize drops Hangul, kana and Han, so a name with any is matched only
    # exactly ("클래식 2" is not "모던 2"). With create_only: true, such a theme is refused
    # (NameTaken) instead.
    class Loader
      THEME_FIELDS = %w[base_body_font base_body_font_size base_heading_font description].freeze
      # Never applied from a file: ids, ownership, timestamps.
      SKIPPED = %w[id created_at updated_at theme_id paper_size_id document_design_id styleable_type styleable_id
                   user_id book_id source_theme_id imported_at source_file].freeze
      # Roles a heading font is read from, first found. Not h1: the title is the heading
      # box's `title`, and h1 is no style (it only divides documents in an import).
      HEADING_ROLES = %w[title h2].freeze
      NOT_ROLES = %w[h1].freeze
      # A derived size within SIZE_TOLERANCE_MM of a PaperSize::STANDARD_SIZES entry takes its
      # local_name (the name book_write finds a book's size by); else it is named by its mm.
      SIZE_TOLERANCE_MM = 0.5
      # designcraft_rb's (doc_processor_rb's) default body line height, pt.
      DEFAULT_LEADING = 22.0
      MM = 25.4 / 72

      attr_reader :package, :name, :locale

      # package: an open DesignCraftRb::BookDesign::Package. font_dir: the book fonts that name
      # the derived styles' fonts (default DesignCraftRb.font_dir; false for none). create_only:
      # raise NameTaken rather than update a system theme the name matches.
      def initialize(package, name: nil, locale: nil, font_dir: nil, create_only: false)
        @package = package
        @name = (name.presence || package.name).to_s.unicode_normalize(:nfc)
        @locale = locale.presence || package.locale
        @font_dir = font_dir
        @create_only = create_only
      end

      # The match and the create are one transaction (Rails' SQLite transactions BEGIN
      # IMMEDIATE, taking the write lock first), so two loads of one name can't both create.
      def load!
        theme = Design::Theme.transaction do
          theme = upsert_theme
          reset_children(theme)
          theme_attributes ? apply_theme(theme) : derive_theme(theme)
          Design::ThemeStyleSeeder.call(theme)
          Design::ParagraphStyleNormalizer.compact!(theme)
          theme
        end
        # Exported only once committed; reloaded for the rows written in plain SQL.
        theme.reload
        Design::ThemeDbExportService.new(theme).export!
        theme
      end

      private

      # The exporter's rows (Exporter#theme_attributes), or nil.
      def theme_attributes = @package.manifest["theme"]

      def page_size_mm = @page_size_mm ||= BookDesignFile.page_size_mm(@package.document)

      def upsert_theme
        theme = matching_theme
        raise NameTaken, "a design named #{name.inspect} (#{locale}) already exists" if theme && @create_only

        theme ||= Design::Theme.system_themes.new(locale: locale)
        theme.assign_attributes(name: name, imported_at: Time.current, source_file: File.basename(@package.path), **theme_row)
        theme.save!
        theme
      end

      # The system theme of this locale named the same (NFC); else, for an all-ASCII name, an
      # all-ASCII one that parameterizes the same.
      def matching_theme
        themes = Design::Theme.system_themes.where(locale: locale).order(:id).to_a
        themes.find { it.name.to_s.unicode_normalize(:nfc) == name } || begin
          slug = name.parameterize if name.ascii_only?
          themes.find { it.name.to_s.ascii_only? && it.name.parameterize == slug } if slug.present?
        end
      end

      def reset_children(theme)
        theme.paper_sizes.destroy_all
        theme.base_paragraph_styles.destroy_all
        theme.table_styles.destroy_all
      end

      def theme_row
        if theme_attributes
          theme_attributes.fetch("theme", {}).slice(*THEME_FIELDS).compact
        else
          body = derived_styles["body"] || {}
          heading = HEADING_ROLES.lazy.filter_map { derived_styles.dig(it, :font) }.first
          { base_body_font: body[:font], base_body_font_size: body[:font_size], base_heading_font: heading || body[:font] }.compact
        end
      end

      # --- the exporter's rows ---------------------------------------------------------------

      def apply_theme(theme)
        Array(theme_attributes["paragraph_styles"]).each { theme.base_paragraph_styles.create!(row(Design::ParagraphStyle, it)) }
        paper_size = create_paper_size(theme, theme_attributes.fetch("paper_size") { raise Error, "manifest.json: theme has no paper_size" })
        Array(theme_attributes["document_designs"]).each { create_document_design(paper_size, it) }
        table_rows(theme_attributes["table_styles"]).each { theme.table_styles.create!(it) }
      end

      # At the inner book's size; the file's override marks, not the ones an explicit creation
      # sets (PaperSize#capture_explicit_overrides marks every field given).
      def create_paper_size(theme, source)
        width, height = page_size_mm
        paper_size = theme.paper_sizes.create!(row(Design::PaperSize, source).merge("width_mm" => width, "height_mm" => height))
        paper_size.update_column(:overridden_fields, source["overridden_fields"]) if source["overridden_fields"].is_a?(Array)
        paper_size
      end

      # Its rows replace what creating it generated (DefaultGenerator's scaled headings).
      def create_document_design(paper_size, source)
        design = paper_size.document_designs.create!(row(Design::DocumentDesign, source))
        styles = Array(source["paragraph_styles"])
        design.paragraph_styles.where.not(name: styles.map { it["name"] }).delete_all
        Array(source["heading_elements"]).each { design.heading_elements.create!(row(Design::HeadingElement, it)) }
        styles.each { design.upsert_paragraph_style!(it["name"], row(Design::ParagraphStyle, it).symbolize_keys) }
      end

      # A document type's own table styles only where the host's table has the column.
      def table_rows(rows)
        Array(rows).reject { it["doc_type"].present? && !Design::TableStyle.typed? }.map { row(Design::TableStyle, it) }
      end

      # The source's fields the model has (a host may lack some), less ids and timestamps.
      def row(model, source)
        source.to_h.slice(*model.column_names).except(*SKIPPED)
      end

      # --- derived from the inner book -------------------------------------------------------

      def derive_theme(theme)
        create_role_styles(theme)
        paper_size = theme.paper_sizes.create!(derived_paper_size)
        # Every doc type from the defaults, then the generated heading sizes on chapter and the
        # title pages dropped: the book's styles are this size's already.
        Design::PaperSizeSeeder.call(paper_size)
        Design::ParagraphStyle.where(styleable: paper_size.document_designs, name: derived_styles.keys).delete_all
        apply_columns(paper_size)
      end

      def create_role_styles(theme)
        derived_styles.each do |role, attributes|
          theme.base_paragraph_styles.find_or_initialize_by(name: role).update!(style_columns(attributes))
        end
        # The theme-level publisher, as ThemeStyleSeeder seeds a new theme's (it would otherwise
        # take this for a theme from before title pages had their own heading styles).
        return if derived_styles.key?("publisher")

        seed = Design::HeadingStyleSeparation.publisher_seed(derived_styles["body"]&.stringify_keys, theme.attributes)
        theme.base_paragraph_styles.create!(Design::ParagraphStyle::STYLE_FIELDS.index_with(nil).merge(seed, "name" => "publisher"))
      end

      # {role => ParagraphStyle attributes} from the book's styles: manifest `styles`, or the
      # book's own names (an exported design's are the roles).
      def derived_styles
        @derived_styles ||= role_map.filter_map do |role, style_name|
          attributes = document_styles.attributes(style_name, line_height: body_leading) or next
          korean_name = style_name unless style_name == role
          [ role, attributes.merge(korean_name: korean_name).compact ]
        end.to_h
      end

      # The attributes the host's ParagraphStyle has columns for (font_style, which Styles reads
      # back, is none in this app: there the font name carries the face).
      def style_columns(attributes)
        attributes.slice(*Design::ParagraphStyle.column_names.map(&:to_sym))
      end

      def role_map
        map = @package.styles.select { |role, style| role.present? && style.is_a?(String) }
        map = map.presence || document_styles.names.reject { it.start_with?("[") }.index_with(&:itself)
        map.except(*NOT_ROLES)
      end

      def document_styles
        @document_styles ||= Styles.new(@package.document, font_dir: font_dir)
      end

      def font_dir
        return @font_dir.presence unless @font_dir.nil?

        require "designcraft_rb"
        DesignCraftRb.font_dir
      end

      def derived_paper_size
        width, height = page_size_mm
        margins = body_margins.transform_values { (it * MM).round(2) }
        text_height = (height / MM) - body_margins[:top] - body_margins[:bottom]
        { **size_names(width, height),
          width_mm: width, height_mm: height,
          top_margin_mm: margins[:top], bottom_margin_mm: margins[:bottom],
          left_margin_mm: margins[:inside], right_margin_mm: margins[:outside], binding_margin_mm: 0,
          # Rounded down, so a body line is never shorter than the book's leading (at 1e-6: a
          # text area of exactly 23 lines can divide to 22.9999…).
          body_line_count: [ (text_height / body_leading).round(6).floor, 1 ].max }
      end

      # size_name ("152mmx225mm") and local_name, the name book_write finds a book's size by:
      # a standard size's ("신국판") within SIZE_TOLERANCE_MM, else its mm ("148.2x209.9").
      def size_names(width, height)
        standard = Design::PaperSize::STANDARD_SIZES.find do |s|
          (width - s[:width_mm]).abs <= SIZE_TOLERANCE_MM && (height - s[:height_mm]).abs <= SIZE_TOLERANCE_MM
        end
        w, h = (standard ? standard.values_at(:width_mm, :height_mm) : [ width, height ]).map { format("%g", it) }
        { size_name: "#{w}mmx#{h}mm", local_name: standard&.dig(:local_name) || "#{w}x#{h}" }
      end

      # The body's leading: its style's, else the book's baseline grid, else DEFAULT_LEADING.
      def body_leading
        @body_leading ||= begin
          grid = @package.document.dig("settings", "baselineGrid", "increment")
          document_styles.leading(role_map["body"] || "body") || (grid if grid.is_a?(Numeric) && grid.positive?) || DEFAULT_LEADING
        end
      end

      # The parent (master) page margins of the chapter's first page, or the first body
      # page's; the page's own where it has no parent. {top:, bottom:, inside:, outside:} in pt.
      def body_margins
        @body_margins ||= begin
          page = pages[first_body_page] || pages.first or raise Error, "inner_page.designcraft: no pages"
          margins = (parent_page(page) || page).fetch("margins", nil) || page.fetch("margins", {})
          { top: margins["top"], bottom: margins["bottom"],
            inside: margins["inside"] || margins["left"], outside: margins["outside"] || margins["right"] }
            .transform_values(&:to_f)
        end
      end

      def first_body_page
        types = @package.doc_types
        range = types["chapter"] || types.find { |type, _| Design::DocumentDesign::BODY_FLOW_DOC_TYPES.include?(type) }&.last
        range ? range.first_page : 0
      end

      def pages = @pages ||= Array(@package.document["spreads"]).flat_map { Array(it["pages"]) }

      def parent_page(page)
        parent = Array(@package.document["parents"]).find { it["id"] == page["parent"] } or return
        Array(parent["pages"]).find { it["side"] == page["side"] } || Array(parent["pages"]).first
      end

      # Each doc type's columns from the first of its pages.
      def apply_columns(paper_size)
        paper_size.document_designs.each do |design|
          range = @package.doc_types[design.doc_type] or next
          columns = pages[range.first_page]&.dig("columns")
          next unless columns.is_a?(Hash) && columns["count"].to_i.positive?

          design.update!(column_count: columns["count"].to_i, gutter: columns["gutter"].to_f)
        end
      end
    end
  end
end
