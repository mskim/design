module Design
  module ParagraphStyleActions
    extend ActiveSupport::Concern

    # Requires Design::DocumentDesignEditing to be included on the same controller,
    # which provides: render_paragraph_style_panel, find_panel_style, paragraph_style_params.

    def new
      @paragraph_style = @document_design.paragraph_styles.new
      render_paragraph_style_panel(
        @paragraph_style,
        panel_update_url: helpers.theme_paper_size_document_design_paragraph_styles_path(@theme, @paper_size, @document_design),
        revert_url: nil)
    end

    def create
      @paragraph_style = @document_design.paragraph_styles.new(paragraph_style_params)
      if @paragraph_style.save
        Design::ThemeDbExportService.new(@theme).export!
        render_paragraph_style_panel(
          @paragraph_style,
          panel_update_url: helpers.panel_update_theme_paper_size_document_design_path(@theme, @paper_size, @document_design, level: "document", style_id: @paragraph_style.id),
          revert_url: helpers.revert_theme_paper_size_document_design_paragraph_style_path(@theme, @paper_size, @document_design, @paragraph_style))
      else
        render_paragraph_style_panel(
          @paragraph_style,
          panel_update_url: helpers.theme_paper_size_document_design_paragraph_styles_path(@theme, @paper_size, @document_design),
          revert_url: nil,
          status: :unprocessable_entity)
      end
    end

    def override
      style = @document_design.override_for(params[:name])
      Design::ThemeDbExportService.new(@theme).export! # keep the render .db in sync with the new override
      render_paragraph_style_panel(
        style,
        panel_update_url: helpers.panel_update_theme_paper_size_document_design_path(@theme, @paper_size, @document_design, level: "document", style_id: style.id),
        revert_url: helpers.revert_theme_paper_size_document_design_paragraph_style_path(@theme, @paper_size, @document_design, style))
    end

    def revert
      @document_design.paragraph_styles.find(params[:id]).destroy
      Design::ThemeDbExportService.new(@theme).export!
      render Design::Views::DocumentDesigns::PropertiesPanel.new(theme: @theme, paper_size: @paper_size, document_design: @document_design, editable: editable?)
    end
  end
end
