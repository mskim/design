module Design
  class ThemeParagraphStylesController < Design::ApplicationController
    before_action :set_theme
    before_action :set_paragraph_style
    before_action :ensure_theme_editable

    def edit
      render form_component
    end

    def update
      if @paragraph_style.update(paragraph_style_params)
        Design::ThemeDbExportService.new(@theme).export!
        redirect_to design.theme_path(@theme), notice: "Style updated."
      else
        render form_component, status: :unprocessable_entity
      end
    end

    private

    def form_component
      Design::Views::ParagraphStyles::Form.new(
        paragraph_style: @paragraph_style,
        form_url: helpers.theme_theme_paragraph_style_path(@theme, @paragraph_style),
        cancel_url: helpers.theme_path(@theme),
        crumbs: [
          [ @theme.name, helpers.theme_path(@theme) ],
          [ @paragraph_style.name, nil ]
        ]
      )
    end

    def set_paragraph_style
      @paragraph_style = @theme.base_paragraph_styles.find(params[:id])
    end

    def paragraph_style_params
      params.require(:paragraph_style).permit(
        :name, :korean_name, :font, :font_size, :scale,
        :text_color, :text_align, :tracking, :space_width, :text_line_spacing,
        :first_line_indent, :left_indent, :right_indent,
        :space_before, :space_after, :space_before_in_lines, :space_after_in_lines,
        :bold_font, :bold_text_color, :emphasis_font, :emphasis_color,
        :fill_type, :fill_color, :fill_ending_color, :fill_gradient_direction,
        :border_thickness, :border_color, :border_side, :rounded_corners, :corner_radius,
        :padding_top, :padding_bottom
      )
    end
  end
end
