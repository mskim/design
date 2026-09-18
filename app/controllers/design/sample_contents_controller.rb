module Design
  # Edits the shared, per-locale sample text used by previews. Any designer may edit
  # (ApplicationController#authorize_designer! already enforces that); the content is
  # shared across themes, so this is deliberately not gated on theme editability.
  class SampleContentsController < Design::ApplicationController
    before_action :set_theme
    before_action :set_content

    def edit
      render edit_component(@content.raw.to_s)
    end

    def update
      @content.save(params[:content].to_s)
      redirect_to return_url, notice: t("design.sample_contents.saved_notice")
    rescue Design::SampleContent::InvalidContent => e
      render edit_component(params[:content].to_s, error: e.message), status: :unprocessable_entity
    end

    def restore
      @content.restore_default!
      redirect_to return_url, notice: t("design.sample_contents.restored_notice")
    end

    private

    def set_content
      @doc_type = params[:doc_type].to_s
      return head :not_found unless Design::DocumentDesign::ALL_DOC_TYPES.include?(@doc_type)
      @content = Design::SampleContent.for(doc_type: @doc_type, locale: @theme.locale)
    end

    # to_s: a nested or array return_to (return_to[a]=1) is ignored.
    def return_design
      return @return_design if defined?(@return_design)
      id = params[:return_to].to_s
      @return_design = id.present? ? @theme.document_designs.find_by(id: id) : nil
    end

    def return_url
      dd = return_design
      dd ? design.edit_theme_paper_size_document_design_path(@theme, dd.paper_size, dd) : design.theme_path(@theme)
    end

    def edit_component(text, error: nil)
      Design::Views::SampleContents::Edit.new(
        theme: @theme, doc_type: @doc_type, content: @content, text: text, error: error,
        return_design: return_design)
    end
  end
end
