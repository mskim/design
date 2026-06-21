# IMPORTANT: This seeder must stay in sync with
# book_design/app/services/theme_style_seeder.rb. Cross-app integration
# test in book_write enforces consistency.
module Design
  class ThemeStyleSeeder
    DEFAULTS = {
      "grid" => {
        border_width: 0.5, border_color: "#333333", border_style: "full",
        header_background: "#ebebeb", alternate_row_background: nil,
        header_text_color: "#000000", body_text_color: "#000000",
        cell_padding: 4, outer_border_width: 0.5,
        header_separator_width: nil, header_font_weight: "bold"
      },
      "zebra" => {
        border_width: 0.5, border_color: "#666666", border_style: "full",
        header_background: "#cccccc", alternate_row_background: "#f7f7f7",
        header_text_color: "#000000", body_text_color: "#000000",
        cell_padding: 4, outer_border_width: 0.5,
        header_separator_width: nil, header_font_weight: "bold"
      },
      "striped" => {
        border_width: 0.5, border_color: "#999999", border_style: "horizontal",
        header_background: nil, alternate_row_background: "#f7f7f7",
        header_text_color: "#000000", body_text_color: "#000000",
        cell_padding: 4, outer_border_width: 1.0,
        header_separator_width: nil, header_font_weight: "bold"
      },
      "minimal" => {
        border_width: 0, border_color: "#ffffff", border_style: "none",
        header_background: "#f0f0f0", alternate_row_background: nil,
        header_text_color: "#000000", body_text_color: "#000000",
        cell_padding: 6, outer_border_width: 0,
        header_separator_width: nil, header_font_weight: "bold"
      },
      "simple" => {
        border_width: 0.5, border_color: "#666666", border_style: "outer_only",
        header_background: nil, alternate_row_background: nil,
        header_text_color: "#000000", body_text_color: "#000000",
        cell_padding: 5, outer_border_width: 1.0,
        header_separator_width: 1.5, header_font_weight: "bold"
      }
    }.freeze

    CELL_DEFAULTS = {
      "table_heading_cell" => {
        text_align: "center", vertical_align: "middle",
        space_before: 2.0, space_after: 2.0
      },
      "table_body_cell" => {
        text_align: "left", vertical_align: "top",
        space_before: 2.0, space_after: 2.0
      }
    }.freeze

    def self.call(theme)
      new(theme).call
    end

    def self.reset(theme, name)
      new(theme).reset(name)
    end

    def initialize(theme)
      @theme = theme
    end

    def call
      seed_table_styles
      seed_cell_paragraph_styles
    end

    def reset(name)
      raise ArgumentError, "unknown style: #{name}" unless DEFAULTS.key?(name)
      style = @theme.table_styles.find_or_initialize_by(name: name)
      style.update!(DEFAULTS[name])
    end

    private

    def seed_table_styles
      DEFAULTS.each do |name, attrs|
        @theme.table_styles.find_or_create_by!(name: name) do |s|
          s.assign_attributes(attrs)
        end
      end
    end

    def seed_cell_paragraph_styles
      heading_font = @theme.base_heading_font
      body_font    = @theme.base_body_font
      body_size    = @theme.base_body_font_size

      @theme.base_paragraph_styles.find_or_create_by!(name: "table_heading_cell") do |s|
        s.assign_attributes(
          font: heading_font,
          font_size: body_size && (body_size + 1.0),
          text_color: "#000000",
          **CELL_DEFAULTS["table_heading_cell"]
        )
      end

      @theme.base_paragraph_styles.find_or_create_by!(name: "table_body_cell") do |s|
        s.assign_attributes(
          font: body_font,
          font_size: body_size,
          text_color: "#000000",
          **CELL_DEFAULTS["table_body_cell"]
        )
      end
    end
  end
end
