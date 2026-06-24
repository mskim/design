module Design
  class TableStyleResolver
    def self.call(theme, table_style)
      new(theme, table_style).call
    end

    def initialize(theme, table_style)
      @theme = theme
      @table_style = table_style
    end

    def call
      {
        name: @table_style.name,
        border_width: @table_style.border_width.to_f,
        border_color: Design::HexToCmyk.call(@table_style.border_color),
        border_style: (@table_style.border_style || "full").to_sym,
        header_background: Design::HexToCmyk.call(@table_style.header_background),
        header_font_weight: (@table_style.header_font_weight || "bold").to_sym,
        header_text_color: Design::HexToCmyk.call(@table_style.header_text_color),
        body_background: nil,
        alternate_row_background: Design::HexToCmyk.call(@table_style.alternate_row_background),
        body_text_color: Design::HexToCmyk.call(@table_style.body_text_color),
        cell_padding: @table_style.cell_padding.to_f,
        outer_border_width: @table_style.outer_border_width.to_f,
        header_separator_width: @table_style.header_separator_width&.to_f,
        header_cell_paragraph_style: paragraph_hash("table_heading_cell"),
        body_cell_paragraph_style:   paragraph_hash("table_body_cell")
      }
    end

    private

    def paragraph_hash(name)
      ps = @theme.base_paragraph_styles.find_by(name: name)
      return nil unless ps
      {
        font: ps.font,
        font_size: ps.font_size&.to_f,
        text_align: ps.text_align,
        vertical_align: ps.vertical_align,
        text_color: ps.text_color,
        padding_top: ps.space_before&.to_f,
        padding_bottom: ps.space_after&.to_f
      }
    end
  end
end
