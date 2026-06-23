require "sqlite3"

module Design
  class ThemeImportService
    SUPPORTED_SCHEMA_VERSION = 2
    class UnsupportedSchemaVersion < StandardError; end

    def self.import_all(dir = Rails.root.join("db/themes_source"))
      Dir.glob(File.join(dir, "*.book_design")).sort.map { |path| new(path).import! }
    end

    def initialize(file_path)
      @file_path = file_path.to_s
    end

    def import!
      db = SQLite3::Database.new(@file_path)
      db.results_as_hash = true
      validate_schema_version!(db)

      Design::Theme.transaction do
        theme = upsert_theme(db)
        reset_children(theme)
        import_base_paragraph_styles(db, theme)
        ps_id_map  = import_paper_sizes(db, theme)
        dd_id_map  = import_document_designs(db, ps_id_map)
        import_heading_elements(db, dd_id_map)
        import_design_paragraph_styles(db, dd_id_map)
        Design::ThemeStyleSeeder.call(theme) # .book_design v2 has no table_styles; re-seed defaults
        theme
      end
    ensure
      db&.close
    end

    private

    def validate_schema_version!(db)
      row = db.get_first_row("SELECT value FROM metadata WHERE key = 'schema_version'")
      version = row && row["value"]&.to_i
      if version.nil? || version < 1 || version > SUPPORTED_SCHEMA_VERSION
        raise UnsupportedSchemaVersion,
          "Unsupported .book_design schema version: #{version.inspect} (supported 1..#{SUPPORTED_SCHEMA_VERSION})"
      end
    end

    # Upsert by parameterized name, PRESERVING the existing Design::Theme.id so
    # books referencing design_theme_<id> keep working.
    def upsert_theme(db)
      row = db.get_first_row("SELECT * FROM theme LIMIT 1")
      raise "No theme row in #{@file_path}" unless row
      slug = row["name"].to_s.parameterize
      theme = Design::Theme.system_themes.find_or_initialize_by(name: slug)
      theme.assign_attributes(
        locale: row["locale"].presence || "ko",
        base_body_font: row["base_body_font"],
        base_body_font_size: row["base_body_font_size"],
        base_heading_font: row["base_heading_font"],
        description: row["description"],
        imported_at: Time.current,
        source_file: File.basename(@file_path)
      )
      theme.save!
      theme
    end

    def reset_children(theme)
      theme.paper_sizes.destroy_all          # cascades document_designs -> dd styles + heading_elements
      theme.base_paragraph_styles.destroy_all
      theme.table_styles.destroy_all
    end

    def import_base_paragraph_styles(db, theme)
      db.execute("SELECT * FROM paragraph_styles WHERE styleable_type = 'theme'").each do |row|
        theme.base_paragraph_styles.create!(paragraph_style_attrs(row))
      end
    end

    def import_paper_sizes(db, theme)
      map = {}
      db.execute("SELECT * FROM paper_sizes ORDER BY id").each do |row|
        ps = theme.paper_sizes.create!(
          size_name: row["size_name"], local_name: row["local_name"],
          width_mm: row["width_mm"], height_mm: row["height_mm"],
          left_margin_mm: row["left_margin_mm"], top_margin_mm: row["top_margin_mm"],
          right_margin_mm: row["right_margin_mm"], bottom_margin_mm: row["bottom_margin_mm"],
          binding_margin_mm: row["binding_margin_mm"],
          body_line_count: row["body_line_count"], toc_page_count: row["toc_page_count"]
        )
        map[row["id"]] = ps
      end
      map
    end

    def import_document_designs(db, ps_id_map)
      map = {}
      db.execute("SELECT * FROM document_designs ORDER BY id").each do |row|
        ps = ps_id_map[row["paper_size_id"]]
        unless ps
          Rails.logger.warn "[ThemeImportService] document_design id=#{row['id']} doc_type=#{row['doc_type']} references unknown paper_size_id=#{row['paper_size_id']} — skipped"
          next
        end
        dd = ps.document_designs.create!(document_design_attrs(row))
        map[row["id"]] = dd
      end
      map
    end

    def import_heading_elements(db, dd_id_map)
      db.execute("SELECT * FROM heading_elements ORDER BY id").each do |row|
        dd = dd_id_map[row["document_design_id"]]
        unless dd
          Rails.logger.warn "[ThemeImportService] heading_element id=#{row['id']} references unknown document_design_id=#{row['document_design_id']} — skipped"
          next
        end
        dd.heading_elements.create!(
          element_type: row["element_type"], style_name: row["style_name"], position: row["position"]
        )
      end
    end

    def import_design_paragraph_styles(db, dd_id_map)
      db.execute("SELECT * FROM paragraph_styles WHERE styleable_type = 'document_design'").each do |row|
        dd = dd_id_map[row["styleable_id"]]
        unless dd
          Rails.logger.warn "[ThemeImportService] paragraph_style '#{row['name']}' references unknown document_design styleable_id=#{row['styleable_id']} — skipped"
          next
        end
        # Creating the document_design fired DefaultGenerator, which may have
        # produced generator-default overrides (e.g. scaled heading sizes) under
        # the same name. The imported .book_design is authoritative, so upsert by
        # name rather than blindly create! (which would collide on uniqueness).
        attrs = paragraph_style_attrs(row)
        dd.upsert_paragraph_style!(attrs[:name], attrs)
      end
    end

    def paragraph_style_attrs(row)
      {
        name: row["name"], korean_name: row["korean_name"], font: row["font"],
        font_size: row["font_size"], text_color: row["text_color"], text_align: row["text_align"],
        tracking: row["tracking"], space_width: row["space_width"], scale: row["scale"],
        first_line_indent: row["first_line_indent"], text_line_spacing: row["text_line_spacing"],
        left_indent: row["left_indent"], right_indent: row["right_indent"],
        space_before: row["space_before"], space_after: row["space_after"],
        space_before_in_lines: row["space_before_in_lines"], space_after_in_lines: row["space_after_in_lines"],
        bold_font: row["bold_font"], bold_text_color: row["bold_text_color"],
        emphasis_font: row["emphasis_font"], emphasis_color: row["emphasis_color"],
        fill_type: row["fill_type"], fill_color: row["fill_color"],
        fill_ending_color: row["fill_ending_color"], fill_gradient_direction: row["fill_gradient_direction"],
        border_thickness: row["border_thickness"], border_color: row["border_color"],
        border_side: row["border_side"], rounded_corners: row["rounded_corners"],
        corner_radius: row["corner_radius"], padding_top: row["padding_top"], padding_bottom: row["padding_bottom"]
      }
    end

    def document_design_attrs(row)
      {
        doc_type: row["doc_type"], layout_class: row["layout_class"],
        column_count: row["column_count"], gutter: row["gutter"],
        heading_height_in_lines: row["heading_height_in_lines"], heading_v_align: row["heading_v_align"],
        heading_bg_type: row["heading_bg_type"], heading_bg_color: row["heading_bg_color"],
        heading_bg_gradient_start: row["heading_bg_gradient_start"], heading_bg_gradient_end: row["heading_bg_gradient_end"],
        heading_bg_gradient_angle: row["heading_bg_gradient_angle"], page_bg_color: row["page_bg_color"],
        text_box_anchor_position: row["text_box_anchor_position"], text_box_grid_width: row["text_box_grid_width"],
        text_box_grid_height: row["text_box_grid_height"],
        has_header: row["has_header"] == 1, has_footer: row["has_footer"] == 1,
        show_header_footer_on_first_page: row["show_header_footer_on_first_page"] == 1,
        header_left_y_offset: row["header_left_y_offset"], header_left_content_string: row["header_left_content_string"],
        header_right_y_offset: row["header_right_y_offset"], header_right_content_string: row["header_right_content_string"],
        footer_left_y_offset: row["footer_left_y_offset"], footer_left_content_string: row["footer_left_content_string"],
        footer_right_y_offset: row["footer_right_y_offset"], footer_right_content_string: row["footer_right_content_string"],
        has_document_cover: row["has_document_cover"] == 1, cover_type: row["cover_type"],
        page_count: row["page_count"], page_type: row["page_type"], v_alignment: row["v_alignment"],
        footnote_type: row["footnote_type"], footnote_char: row["footnote_char"], footnote_range: row["footnote_range"]
      }
    end
  end
end
