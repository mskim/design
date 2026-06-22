module Design
  class ThemeDbExportService
    def self.themes_dir
      Design.themes_dir
    end

    # Map namespaced to non-namespaced for SQLite compatibility with PdfGenerationService
    STYLEABLE_TYPE_MAP = {
      "Design::Theme" => "Theme",
      "Design::PaperSize" => "PaperSize",
      "Design::DocumentDesign" => "DocumentDesign"
    }.freeze

    def initialize(theme)
      @theme = theme
    end

    def export!
      dir = export_dir
      FileUtils.mkdir_p(dir)
      db_path = File.join(dir, "#{@theme.name.parameterize}.db")
      File.delete(db_path) if File.exist?(db_path)

      db = SQLite3::Database.new(db_path)
      create_tables(db)
      insert_theme(db)
      insert_base_styles(db)
      insert_paper_sizes_and_designs(db)
      insert_table_styles(db)
      db.close

      db_path
    end

    def export_dir
      base = self.class.themes_dir
      if @theme.system?
        base
      else
        File.join(base, "user_#{@theme.user_id}")
      end
    end

    private

    def create_tables(db)
      db.execute_batch(<<~SQL)
        CREATE TABLE themes (
          id INTEGER PRIMARY KEY, name TEXT NOT NULL, locale TEXT NOT NULL,
          base_body_font TEXT, base_body_font_size REAL, base_heading_font TEXT,
          description TEXT, created_at DATETIME, updated_at DATETIME
        );
        CREATE TABLE paper_sizes (
          id INTEGER PRIMARY KEY, theme_id INTEGER NOT NULL REFERENCES themes(id),
          size_name TEXT NOT NULL, local_name TEXT,
          width_mm REAL NOT NULL, height_mm REAL NOT NULL,
          left_margin_mm REAL DEFAULT 0, top_margin_mm REAL DEFAULT 0,
          right_margin_mm REAL DEFAULT 0, bottom_margin_mm REAL DEFAULT 0,
          binding_margin_mm REAL DEFAULT 0, body_line_count INTEGER DEFAULT 23,
          toc_page_count INTEGER, created_at DATETIME, updated_at DATETIME
        );
        CREATE TABLE document_designs (
          id INTEGER PRIMARY KEY, paper_size_id INTEGER NOT NULL REFERENCES paper_sizes(id),
          doc_type TEXT NOT NULL, heading_height_in_lines INTEGER DEFAULT 6,
          heading_v_align TEXT DEFAULT 'center', toc_v_align TEXT DEFAULT 'bottom',
          column_count INTEGER DEFAULT 1,
          gutter REAL DEFAULT 10.0, has_header BOOLEAN DEFAULT 0, has_footer BOOLEAN DEFAULT 0,
          header_left_content_string TEXT, header_right_content_string TEXT,
          footer_left_content_string TEXT, footer_right_content_string TEXT,
          header_left_y_offset REAL, header_right_y_offset REAL,
          footer_left_y_offset REAL, footer_right_y_offset REAL,
          show_header_footer_on_first_page BOOLEAN DEFAULT 0,
          heading_bg_type TEXT, heading_bg_color TEXT, page_bg_color TEXT,
          text_box_anchor_position TEXT, text_box_grid_width INTEGER, text_box_grid_height INTEGER,
          v_alignment TEXT, body_line_count INTEGER,
          cover_type TEXT, footnote_char TEXT, footnote_range TEXT, footnote_type TEXT,
          has_document_cover BOOLEAN DEFAULT 0,
          heading_bg_gradient_angle REAL, heading_bg_gradient_start TEXT, heading_bg_gradient_end TEXT,
          page_type TEXT,
          created_at DATETIME, updated_at DATETIME
        );
        CREATE TABLE paragraph_styles (
          id INTEGER PRIMARY KEY, styleable_type TEXT NOT NULL, styleable_id INTEGER NOT NULL,
          name TEXT NOT NULL, korean_name TEXT, font TEXT, font_size REAL,
          text_color TEXT, text_align TEXT, tracking REAL, space_width REAL, scale REAL,
          first_line_indent REAL, text_line_spacing REAL,
          space_before REAL, space_after REAL,
          space_before_in_lines REAL, space_after_in_lines REAL,
          left_indent REAL, right_indent REAL,
          bold_font TEXT, bold_text_color TEXT, emphasis_color TEXT, emphasis_font TEXT,
          fill_type TEXT, fill_color TEXT, fill_ending_color TEXT, fill_gradient_direction TEXT,
          border_thickness REAL, border_color TEXT, border_side TEXT,
          rounded_corners TEXT, corner_radius TEXT,
          padding_top REAL, padding_bottom REAL,
          vertical_align TEXT,
          created_at DATETIME, updated_at DATETIME
        );
        CREATE TABLE table_styles (
          id INTEGER PRIMARY KEY,
          theme_id INTEGER NOT NULL REFERENCES themes(id),
          name TEXT NOT NULL,
          border_width REAL, border_color TEXT, border_style TEXT,
          header_background TEXT, alternate_row_background TEXT,
          header_text_color TEXT, body_text_color TEXT,
          cell_padding REAL, outer_border_width REAL,
          header_separator_width REAL, header_font_weight TEXT,
          created_at DATETIME, updated_at DATETIME
        );
        CREATE TABLE heading_elements (
          id INTEGER PRIMARY KEY, document_design_id INTEGER NOT NULL REFERENCES document_designs(id),
          element_type TEXT NOT NULL, style_name TEXT, position INTEGER,
          created_at DATETIME, updated_at DATETIME
        );
      SQL
    end

    def insert_theme(db)
      db.execute(
        "INSERT INTO themes VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [ @theme.id, @theme.name, @theme.locale, @theme.base_body_font,
          f(@theme.base_body_font_size), @theme.base_heading_font, @theme.description,
          @theme.created_at&.iso8601, @theme.updated_at&.iso8601 ]
      )
    end

    def insert_base_styles(db)
      @theme.base_paragraph_styles.each { |style| insert_style(db, style) }
    end

    def insert_paper_sizes_and_designs(db)
      @theme.paper_sizes.each do |ps|
        db.execute(
          "INSERT INTO paper_sizes VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
          [ ps.id, ps.theme_id, ps.size_name, ps.local_name,
            f(ps.width_mm), f(ps.height_mm), f(ps.left_margin_mm), f(ps.top_margin_mm),
            f(ps.right_margin_mm), f(ps.bottom_margin_mm), f(ps.binding_margin_mm),
            ps.body_line_count, ps.toc_page_count,
            ps.created_at&.iso8601, ps.updated_at&.iso8601 ]
        )

        ps.document_designs.each do |dd|
          db.execute(<<~SQL, document_design_values(dd))
            INSERT INTO document_designs (
              id, paper_size_id, doc_type,
              heading_height_in_lines, heading_v_align, toc_v_align,
              column_count, gutter,
              has_header, has_footer,
              header_left_content_string, header_right_content_string,
              footer_left_content_string, footer_right_content_string,
              header_left_y_offset, header_right_y_offset,
              footer_left_y_offset, footer_right_y_offset,
              show_header_footer_on_first_page,
              heading_bg_type, heading_bg_color, page_bg_color,
              text_box_anchor_position, text_box_grid_width, text_box_grid_height,
              v_alignment, body_line_count,
              cover_type, footnote_char, footnote_range, footnote_type,
              has_document_cover,
              heading_bg_gradient_angle, heading_bg_gradient_start, heading_bg_gradient_end,
              page_type,
              created_at, updated_at
            ) VALUES (#{Array.new(38, "?").join(", ")})
          SQL

          dd.paragraph_styles.each { |style| insert_style(db, style) }

          dd.heading_elements.each do |he|
            db.execute(
              "INSERT INTO heading_elements VALUES (?, ?, ?, ?, ?, ?, ?)",
              [ he.id, he.document_design_id, he.element_type, he.style_name,
                he.position, he.created_at&.iso8601, he.updated_at&.iso8601 ]
            )
          end
        end
      end
    end

    def document_design_values(dd)
      [ dd.id, dd.paper_size_id, dd.doc_type,
        dd.heading_height_in_lines, dd.heading_v_align, dd.toc_v_align,
        dd.column_count, f(dd.gutter),
        dd.has_header ? 1 : 0, dd.has_footer ? 1 : 0,
        dd.header_left_content_string, dd.header_right_content_string,
        dd.footer_left_content_string, dd.footer_right_content_string,
        f(dd.header_left_y_offset), f(dd.header_right_y_offset),
        f(dd.footer_left_y_offset), f(dd.footer_right_y_offset),
        dd.show_header_footer_on_first_page ? 1 : 0,
        dd.heading_bg_type, dd.heading_bg_color, dd.page_bg_color,
        dd.text_box_anchor_position, dd.text_box_grid_width, dd.text_box_grid_height,
        dd.v_alignment, dd.body_line_count,
        dd.cover_type, dd.footnote_char, dd.footnote_range, dd.footnote_type,
        dd.has_document_cover ? 1 : 0,
        f(dd.heading_bg_gradient_angle), dd.heading_bg_gradient_start, dd.heading_bg_gradient_end,
        dd.page_type,
        dd.created_at&.iso8601, dd.updated_at&.iso8601 ]
    end

    def insert_style(db, style)
      styleable_type = STYLEABLE_TYPE_MAP.fetch(style.styleable_type, style.styleable_type)

      db.execute(
        "INSERT INTO paragraph_styles VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [ style.id, styleable_type, style.styleable_id,
          style.name, style.korean_name, style.font, f(style.font_size),
          style.text_color, style.text_align, f(style.tracking), f(style.space_width),
          f(style.scale), f(style.first_line_indent), f(style.text_line_spacing),
          f(style.space_before), f(style.space_after),
          f(style.space_before_in_lines), f(style.space_after_in_lines),
          f(style.left_indent), f(style.right_indent),
          style.bold_font, style.bold_text_color, style.emphasis_color, style.emphasis_font,
          style.fill_type, style.fill_color, style.fill_ending_color, style.fill_gradient_direction,
          f(style.border_thickness), style.border_color, style.border_side,
          style.rounded_corners, style.corner_radius,
          f(style.padding_top), f(style.padding_bottom),
          style.vertical_align,
          style.created_at&.iso8601, style.updated_at&.iso8601 ]
      )
    end

    def insert_table_styles(db)
      sql = <<~SQL
        INSERT INTO table_styles (
          id, theme_id, name, border_width, border_color, border_style,
          header_background, alternate_row_background,
          header_text_color, body_text_color,
          cell_padding, outer_border_width, header_separator_width,
          header_font_weight, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL

      @theme.table_styles.each do |ts|
        db.execute(sql,
          [ ts.id, ts.theme_id, ts.name,
            f(ts.border_width), ts.border_color, ts.border_style,
            ts.header_background, ts.alternate_row_background,
            ts.header_text_color, ts.body_text_color,
            f(ts.cell_padding), f(ts.outer_border_width), f(ts.header_separator_width),
            ts.header_font_weight, ts.created_at&.iso8601, ts.updated_at&.iso8601 ]
        )
      end
    end

    def f(val)
      val&.to_f
    end
  end
end
