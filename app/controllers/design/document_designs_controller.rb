module Design
  class DocumentDesignsController < Design::ApplicationController
    include Design::DocumentDesignEditing
    include Design::ParagraphStyleActions

    before_action :set_theme
    before_action :set_paper_size
    before_action :set_document_design
    before_action :ensure_theme_editable, except: [ :preview_jpg ]

    def edit
      @paragraph_styles = @document_design.paragraph_styles.order(:name)
      render Design::Views::DocumentDesigns::Edit.new(theme: @theme, paper_size: @paper_size, document_design: @document_design, paragraph_styles: @paragraph_styles, editable: editable?)
    end

    def update
      if @document_design.update(document_design_params)
        Design::ThemeDbExportService.new(@theme).export!
        redirect_to helpers.edit_theme_paper_size_document_design_path(@theme, @paper_size, @document_design), notice: "Document design updated."
      else
        render Design::Views::DocumentDesigns::Edit.new(theme: @theme, paper_size: @paper_size, document_design: @document_design, paragraph_styles: @document_design.paragraph_styles.order(:name), editable: editable?), status: :unprocessable_entity
      end
    end

    private

    def set_paper_size
      @paper_size = @theme.paper_sizes.find(params[:paper_size_id])
    end

    def set_document_design
      @document_design = @paper_size.document_designs.find(params[:document_design_id] || params[:id])
    end
  end
end
