module Design
  class PaperSizesController < Design::ApplicationController
    before_action :set_theme
    before_action :set_paper_size
    before_action :ensure_theme_editable

    def edit
      @base_styles = @paper_size.paragraph_styles.order(:name)
      render Design::Views::PaperSizes::Edit.new(theme: @theme, paper_size: @paper_size, base_styles: @base_styles)
    end

    def update
      if @paper_size.update(paper_size_params)
        Design::ThemeDbExportService.new(@theme).export!
        redirect_to design.theme_path(@theme), notice: "Paper size updated."
      else
        render Design::Views::PaperSizes::Edit.new(theme: @theme, paper_size: @paper_size, base_styles: @paper_size.paragraph_styles.order(:name)), status: :unprocessable_entity
      end
    end

    private

    def set_paper_size
      @paper_size = @theme.paper_sizes.find(params[:id])
    end

    def paper_size_params
      params.require(:paper_size).permit(
        :left_margin_mm, :top_margin_mm, :right_margin_mm, :bottom_margin_mm,
        :binding_margin_mm, :body_line_count, :toc_page_count
      )
    end
  end
end
