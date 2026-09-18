module Design
  # A doc type's paragraph style, keyed by name (D2b). Writes go through
  # DocumentDesign's field-level operations — which apply to this doc type on
  # every paper size — then re-export the theme .db and answer with turbo
  # streams: a morph of the panel's #style-panel-content and, unless
  # render_preview=0 (more saves are queued), the preview frame.
  class DocumentDesignStylesController < Design::ApplicationController
    include Design::DocumentDesignPreview

    RESERVED_STYLE_NAMES = %w[new].freeze # styles/new is the form

    before_action :set_theme
    before_action :set_paper_size
    before_action :set_document_design
    before_action :ensure_theme_editable
    # `only:` lists, never `except: [:new, :create]` — raise_on_missing_callback_actions.
    before_action :ensure_style_exists, only: [ :show, :update_field, :revert_field, :destroy, :push ]
    before_action :ensure_style_field, only: [ :update_field, :revert_field ]

    # GET styles/:name — embedded in the design editor (a properties_panel
    # frame request) or the full-page editor (preview-overlay clicks).
    def show
      if turbo_frame_request?
        render embedded_panel
      else
        render Design::Views::ParagraphStyles::EditPage.new(
          theme: @theme, paper_size: @paper_size, document_design: @document_design, style_name: style_name,
          urls: style_urls(preview_mode: "single"), back_url: editor_url, editable: editable?)
      end
    end

    # GET styles/new
    def new
      render new_style_form
    end

    # POST styles (name, korean_name). A name no layer defines becomes an empty
    # row on every size of this doc type; an existing one just opens.
    def create
      name = params[:name].to_s.strip
      korean = params[:korean_name].to_s.strip.presence
      if (error = new_style_error(name))
        return render turbo_stream: turbo_stream.replace("properties_panel", new_style_form(name: name, korean_name: korean, error: error)),
                      status: :unprocessable_entity
      end
      unless @document_design.style_exists?(name)
        @document_design.create_style!(name, korean_name: korean)
        Design::ThemeDbExportService.new(@theme).export!
      end
      @style_name = name
      render turbo_stream: turbo_stream.replace("properties_panel", embedded_panel)
    end

    # PATCH styles/:name/field (field, value). The value is validated on the
    # row it lands on for this size (existing or new); a failure writes nothing.
    # Only a string (or nothing) is a value: value[]= / value[a]= are a 400.
    def update_field
      value = params[:value]
      return head(:bad_request) unless value.nil? || value.is_a?(String)
      row = target_row
      row[field] = value&.strip
      return render_invalid_field(row, value) unless row.valid?(:style_panel)

      @document_design.set_style_field!(style_name, field, value)
      render_saved
    end

    # DELETE styles/:name/field (field): back to inherit on every size.
    def revert_field
      @document_design.revert_style_field!(style_name, field)
      render_saved
    end

    # DELETE styles/:name: every field back to inherit on every size.
    def destroy
      @document_design.revert_style!(style_name)
      render_saved
    end

    # POST styles/:name/push: this doc type's user-changed fields to its
    # parent (theme for chapter, chapter for the rest).
    def push
      @document_design.push_style!(style_name)
      render_saved
    rescue Design::DocumentDesign::MissingChapterError => e
      message = I18n.t("design.style_panel.errors.missing_chapter", sizes: e.sizes.join(", "))
      render turbo_stream: panel_streams(error: message), status: :unprocessable_entity
    end

    private

    def set_paper_size
      @paper_size = @theme.paper_sizes.find(params[:paper_size_id])
    end

    def set_document_design
      @document_design = @paper_size.document_designs.find(params[:document_design_id])
    end

    def style_name = @style_name ||= params[:name].to_s
    def field = params[:field].to_s
    def render_preview? = params[:render_preview] != "0"

    def ensure_style_exists
      return if @document_design.style_exists?(style_name)
      action_name == "show" ? fall_back_to_document_view : head(:not_found)
    end

    def ensure_style_field
      head :bad_request unless Design::ParagraphStyle::STYLE_FIELDS.include?(field)
    end

    def target_row
      @document_design.paragraph_styles.find_by(name: style_name) ||
        Design::ParagraphStyle.new(styleable: @document_design, name: style_name)
    end

    def render_invalid_field(row, value)
      messages = row.errors[field].presence || row.errors.full_messages
      render turbo_stream: panel_streams(field_errors: { field => messages }, attempted: { field => value.to_s }),
             status: :unprocessable_entity
    end

    def render_saved
      Design::ThemeDbExportService.new(@theme).export!
      render turbo_stream: panel_streams
    end

    # The panel's content morphed in place, plus the preview unless more saves
    # are queued. The component is the stream content (render_in: no layout —
    # render_to_string would wrap it in the design layout).
    def panel_streams(**content)
      component = Design::Views::ParagraphStyles::StylePanelContent.new(
        document_design: @document_design, style_name: style_name, editable: editable?, **content)
      streams = [ turbo_stream.replace("style-panel-content", component, method: :morph) ]
      streams << preview_frame_stream if render_preview?
      streams
    end

    # The style's endpoints, plus the preview frame's GET URL (in the panel's
    # preview mode), which autosave reloads when a failed save left it stale.
    def style_urls(preview_mode: panel_preview_mode)
      args = [ @theme, @paper_size, @document_design, style_name ]
      { field: helpers.field_theme_paper_size_document_design_style_path(*args),
        style: helpers.theme_paper_size_document_design_style_path(*args),
        push: helpers.push_theme_paper_size_document_design_style_path(*args),
        preview: helpers.preview_theme_paper_size_document_design_path(@theme, @paper_size, @document_design,
                                                                       preview_mode: preview_mode) }
    end

    # The panel embedded in the design editor: Back returns to the 단락정의
    # list inside the same frame.
    def embedded_panel
      Design::Views::ParagraphStyles::StylePanel.new(
        document_design: @document_design, style_name: style_name, urls: style_urls, editable: editable?,
        preview_mode: panel_preview_mode, back_frame: "properties_panel",
        back_url: helpers.properties_panel_theme_paper_size_document_design_path(@theme, @paper_size, @document_design, tab: "typography"))
    end

    def new_style_form(name: nil, korean_name: nil, error: nil)
      Design::Views::ParagraphStyles::NewStyleForm.new(
        url: helpers.theme_paper_size_document_design_styles_path(@theme, @paper_size, @document_design),
        back_url: helpers.properties_panel_theme_paper_size_document_design_path(@theme, @paper_size, @document_design, tab: "typography"),
        name: name, korean_name: korean_name, error: error)
    end

    def new_style_error(name)
      if name.empty? then I18n.t("design.style_panel.errors.name_blank")
      elsif name.include?("/") || RESERVED_STYLE_NAMES.include?(name) then I18n.t("design.style_panel.errors.name_invalid")
      end
    end

    def editor_url
      helpers.edit_theme_paper_size_document_design_path(@theme, @paper_size, @document_design, tab: "typography")
    end
  end
end
