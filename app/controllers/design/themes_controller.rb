module Design
  class ThemesController < Design::ApplicationController
    before_action :set_theme, only: [ :show, :edit, :update, :destroy, :clone, :generate_sizes ]

    def index
      @themes = Design::Theme.order(:name)
      render Design::Views::Themes::Index.new(themes: @themes)
    end

    def show
      @paper_sizes = @theme.paper_sizes.order(:id)
      @selected_paper_size = @paper_sizes.find_by(id: params[:paper_size_id]) || @theme.default_paper_size || @paper_sizes.first
      @document_designs = @selected_paper_size ? interior_document_designs(@selected_paper_size) : []
      render Design::Views::Themes::Show.new(
        theme: @theme, paper_sizes: @paper_sizes,
        selected_paper_size: @selected_paper_size, document_designs: @document_designs
      )
    end

    def new
      render Design::Views::Themes::Form.new(theme: Design::Theme.new(locale: I18n.locale.to_s))
    end

    def create
      @theme = Design::Theme.new(theme_params.merge(user: Design.current_user))
      if @theme.save
        redirect_to theme_path(@theme), notice: t("design.themes.created_notice", name: @theme.name)
      else
        render Design::Views::Themes::Form.new(theme: @theme), status: :unprocessable_entity
      end
    end

    def edit
      return head :forbidden unless @theme.editable_by?(Design.current_user)
      render Design::Views::Themes::Form.new(theme: @theme)
    end

    def update
      return head :forbidden unless @theme.editable_by?(Design.current_user)

      if @theme.update(theme_params)
        redirect_to themes_path, notice: t("design.themes.renamed_notice", name: @theme.name)
      else
        redirect_to themes_path, alert: @theme.errors.full_messages.to_sentence
      end
    end

    def clone
      new_theme = Design::ThemeCloneService.new(@theme, user: Design.current_user, name: params[:name]).clone
      Design::ThemeDbExportService.new(new_theme).export!
      redirect_to theme_path(new_theme), notice: t("design.themes.cloned_notice", name: new_theme.name)
    end

    def generate_sizes
      return head :forbidden unless @theme.editable_by?(Design.current_user)

      Design::SizeGenerationService.new(@theme).generate!
      redirect_to theme_path(@theme), notice: t("design.themes.generated_notice", size: @theme.default_paper_size&.display_name)
    rescue => e
      redirect_to theme_path(@theme), alert: t("design.themes.generate_failed", error: e.message)
    end

    def destroy
      if @theme.editable_by?(Design.current_user)
        @theme.destroy
        redirect_to themes_path, notice: t("design.themes.deleted_notice")
      else
        head :forbidden
      end
    end

    private

    # The theme show page previews interior document pages only. Cover panels
    # (front_page, seneca, …) belong to the cover editor and don't render as
    # interior pages, so they're excluded from the grid.
    def interior_document_designs(paper_size)
      Design::DocumentDesign.interior_for(paper_size)
    end

    def theme_params
      params.require(:theme).permit(:name, :description, :locale, :base_body_font, :base_body_font_size, :base_heading_font)
    end
  end
end
