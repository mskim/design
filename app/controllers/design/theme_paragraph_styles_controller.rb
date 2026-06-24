module Design
  class ThemeParagraphStylesController < Design::ApplicationController
    include Design::ParagraphStyleParams

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
  end
end
