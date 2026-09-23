module Design
  module ParagraphStyleParams
    extend ActiveSupport::Concern

    PERMITTED = %i[
      name korean_name font font_size scale
      text_color text_align tracking space_width text_line_spacing
      first_line_indent left_indent right_indent
      space_before space_after space_before_in_lines space_after_in_lines
      bold_font bold_text_color emphasis_font emphasis_color
      fill_type fill_color fill_ending_color fill_gradient_direction
      border_top_thickness border_right_thickness border_bottom_thickness border_left_thickness
      border_top_color border_right_color border_bottom_color border_left_color
      corner_top_left corner_top_right corner_bottom_right corner_bottom_left
      padding_top padding_bottom
      vertical_align
    ].freeze

    private

    def paragraph_style_params
      params.require(:paragraph_style).permit(*PERMITTED)
    end
  end
end
