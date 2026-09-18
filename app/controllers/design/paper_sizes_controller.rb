module Design
  class PaperSizesController < Design::ApplicationController
    before_action :set_theme
    before_action :set_paper_size, only: [:edit, :update, :destroy, :regenerate]
    before_action :ensure_theme_editable

    def new
      @paper_size = @theme.paper_sizes.new
      render Design::Views::PaperSizes::Form.new(theme: @theme, paper_size: @paper_size)
    end

    def create
      @paper_size = @theme.paper_sizes.new(paper_size_params)
      if @paper_size.save
        Design::PaperSizeSeeder.call(@paper_size)
        Design::ThemeDbExportService.new(@theme).export!
        redirect_to design.edit_theme_paper_size_path(@theme, @paper_size), notice: I18n.t("design.paper_sizes.created_notice")
      else
        render Design::Views::PaperSizes::Form.new(theme: @theme, paper_size: @paper_size), status: :unprocessable_entity
      end
    end

    def edit
      @base_styles = @paper_size.paragraph_styles.order(:name)
      render Design::Views::PaperSizes::Form.new(theme: @theme, paper_size: @paper_size, base_styles: @base_styles,
                                                 return_design: return_design)
    end

    def regenerate
      Design::DefaultGenerator.call(@paper_size)
      Design::ThemeDbExportService.new(@theme).export!
      target = return_design ? return_url : design.edit_theme_paper_size_path(@theme, @paper_size)
      redirect_to target, notice: I18n.t("design.paper_sizes.regenerated_notice")
    end

    # Always the theme page, return_to or not: the editor's paper size is gone.
    def destroy
      @paper_size.destroy
      Design::ThemeDbExportService.new(@theme).export!
      redirect_to design.theme_path(@theme), notice: I18n.t("design.paper_sizes.deleted_notice")
    end

    def update
      if @paper_size.update(paper_size_params)
        @paper_size.mark_overridden_from_changes(Design::PaperSize::GENERATABLE_FIELDS)
        Design::ThemeDbExportService.new(@theme).export!
        redirect_to return_url, notice: I18n.t("design.paper_sizes.updated_notice")
      else
        render Design::Views::PaperSizes::Form.new(theme: @theme, paper_size: @paper_size,
                                                   base_styles: @paper_size.paragraph_styles.order(:name),
                                                   return_design: return_design), status: :unprocessable_entity
      end
    end

    private

    def set_paper_size
      @paper_size = @theme.paper_sizes.find(params[:id])
    end

    # The design editor's 판형 편집 link carries return_to=<document design id>
    # (the sample-content pattern, sample_contents_controller.rb:34-42). Only a
    # design on this paper size counts, so it can never redirect elsewhere.
    # to_s: a nested or array return_to (return_to[a]=1) is ignored.
    def return_design
      return @return_design if defined?(@return_design)
      id = params[:return_to].to_s
      @return_design = id.present? ? @paper_size.document_designs.find_by(id: id) : nil
    end

    def return_url
      return_design ? design.edit_theme_paper_size_document_design_path(@theme, @paper_size, return_design) : design.theme_path(@theme)
    end

    def paper_size_params
      params.require(:paper_size).permit(
        :size_name, :local_name, :width_mm, :height_mm,
        :left_margin_mm, :top_margin_mm, :right_margin_mm, :bottom_margin_mm,
        :binding_margin_mm, :body_line_count, :toc_page_count
      )
    end
  end
end
