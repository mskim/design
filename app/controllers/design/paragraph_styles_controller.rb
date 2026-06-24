module Design
  class ParagraphStylesController < Design::ApplicationController
    include Design::ParagraphStyleParams

    before_action :set_theme
    before_action :set_paper_size
    before_action :set_document_design
    before_action :set_paragraph_style
    before_action :ensure_theme_editable

    def edit
      render form_component
    end

    def update
      if @paragraph_style.update(paragraph_style_params)
        Design::ThemeDbExportService.new(@theme).export!
        redirect_to design.edit_theme_paper_size_document_design_path(@theme, @paper_size, @document_design), notice: "Style updated."
      else
        render form_component, status: :unprocessable_entity
      end
    end

    private

    def form_component
      Design::Views::ParagraphStyles::Form.new(
        paragraph_style: @paragraph_style,
        form_url: helpers.theme_paper_size_document_design_paragraph_style_path(@theme, @paper_size, @document_design, @paragraph_style),
        cancel_url: helpers.edit_theme_paper_size_document_design_path(@theme, @paper_size, @document_design),
        crumbs: [
          [ @theme.name, helpers.theme_path(@theme) ],
          [ @paper_size.display_name, helpers.edit_theme_paper_size_path(@theme, @paper_size) ],
          [ @document_design.doc_type, helpers.edit_theme_paper_size_document_design_path(@theme, @paper_size, @document_design) ],
          [ @paragraph_style.name, nil ]
        ]
      )
    end

    def set_paper_size
      @paper_size = @theme.paper_sizes.find(params[:paper_size_id])
    end

    def set_document_design
      @document_design = @paper_size.document_designs.find(params[:document_design_id])
    end

    def set_paragraph_style
      @paragraph_style = @document_design.paragraph_styles.find(params[:id])
    end
  end
end
