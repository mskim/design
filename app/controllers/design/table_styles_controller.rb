module Design
  class TableStylesController < Design::ApplicationController
    before_action :set_theme
    before_action :set_table_style
    before_action :ensure_theme_editable

    def show
      redirect_to design.edit_theme_table_style_path(@theme, @table_style)
    end

    def edit
      render Design::Views::TableStyles::Edit.new(theme: @theme, table_style: @table_style)
    end

    def update
      if @table_style.update(table_style_params)
        redirect_to design.edit_theme_table_style_path(@theme, @table_style)
      else
        render Design::Views::TableStyles::Edit.new(theme: @theme, table_style: @table_style), status: :unprocessable_entity
      end
    end

    def reset
      Design::ThemeStyleSeeder.reset(@theme, @table_style.name)
      redirect_to design.edit_theme_table_style_path(@theme, @table_style)
    end

    private

    def set_table_style
      @table_style = @theme.table_styles.find(params[:id])
    end

    def table_style_params
      params.require(:table_style).permit(
        :border_width, :border_color, :border_style,
        :header_background, :alternate_row_background,
        :header_text_color, :body_text_color,
        :cell_padding, :outer_border_width, :header_separator_width,
        :header_font_weight
      )
    end
  end
end
