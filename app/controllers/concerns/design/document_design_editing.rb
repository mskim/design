module Design
  module DocumentDesignEditing
    extend ActiveSupport::Concern

    include Design::ParagraphStyleParams

    def preview
      dd = request.post? ? build_preview_design : @document_design
      result = Design::PreviewService.new(dd, paper_size: @paper_size).generate
      component = if result[:success]
        Design::Views::DocumentDesigns::Preview.new(
          document_design: dd, paper_size: @paper_size,
          jpg_url: helpers.preview_jpg_theme_paper_size_document_design_path(@theme, @paper_size, @document_design, t: Time.now.to_i),
          overlay_data: result[:overlay_data], page_width: result[:page_width],
          page_height: result[:page_height], style_urls: build_style_urls)
      else
        Design::Views::DocumentDesigns::PreviewError.new(error: result[:error])
      end

      if request.post?
        render turbo_stream: turbo_stream.replace("preview_frame", html: component.call.html_safe)
      else
        render component
      end
    end

    def preview_jpg
      result = Design::PreviewService.new(@document_design, paper_size: @paper_size).generate
      if result[:success] && File.exist?(result[:jpg_path])
        send_file result[:jpg_path], type: "image/jpeg", disposition: "inline"
      else
        head :not_found
      end
    end

    def properties_panel
      render Design::Views::DocumentDesigns::PropertiesPanel.new(theme: @theme, paper_size: @paper_size, document_design: @document_design, editable: editable?)
    end

    def panel
      style = find_panel_style(params[:level], params[:style_id])
      panel_update_url = helpers.panel_update_theme_paper_size_document_design_path(@theme, @paper_size, @document_design, level: params[:level], style_id: style.id)
      revert_url = document_style_revert_url(style, params[:level])

      # Embedded (typography tab / style list, via a turbo-frame request): just the
      # bare panel that swaps into properties_panel. Full navigation (clicking a
      # style in the preview): a full page with the preview on the left.
      if turbo_frame_request?
        render_paragraph_style_panel(style, panel_update_url: panel_update_url, revert_url: revert_url)
      else
        render Design::Views::ParagraphStyles::EditPage.new(
          paragraph_style: style, theme: @theme, paper_size: @paper_size, document_design: @document_design,
          panel_update_url: panel_update_url,
          back_url: helpers.edit_theme_paper_size_document_design_path(@theme, @paper_size, @document_design),
          revert_url: revert_url, editable: editable?)
      end
    rescue ActiveRecord::RecordNotFound
      # A valid-level style link can outlive its row (reverted to base, or cleared by
      # an "apply to all" save) — degrade to the live document view instead of 500ing.
      # An invalid/unknown level is a malformed request and still 404s.
      raise unless KNOWN_STYLE_LEVELS.include?(params[:level])
      fall_back_to_document_view
    end

    def panel_update
      style = find_panel_style(params[:level], params[:style_id])
      style.assign_attributes(paragraph_style_params) # validate without persisting the clicked record
      if style.valid?
        name = style.name_was || style.name
        if params[:apply_scope] == "all"
          @theme.apply_paragraph_style_to_all!(name, paragraph_style_params)
        else
          @theme.apply_paragraph_style_to_doc_type!(@document_design.doc_type, name, paragraph_style_params)
        end
        Design::ThemeDbExportService.new(@theme).export!
        # Refresh the preview AND the form: re-render the panel against where the
        # value now lives — the document override after a default-scope save (so its
        # revert link appears), or the theme base after "apply to all".
        render turbo_stream: [
          preview_frame_stream,
          saved_panel_stream(name, params[:apply_scope])
        ].compact
      else
        render_paragraph_style_panel(
          style,
          panel_update_url: helpers.panel_update_theme_paper_size_document_design_path(@theme, @paper_size, @document_design, level: params[:level], style_id: style.id),
          revert_url: document_style_revert_url(style, params[:level]),
          status: :unprocessable_entity)
      end
    end

    private

    KNOWN_STYLE_LEVELS = %w[theme paper document].freeze

    # Stale style link (reverted, or cleared by an "apply to all" save): show the
    # live document view instead of raising. A turbo-frame request re-renders the
    # properties panel in place; a full navigation redirects to the editor.
    def fall_back_to_document_view
      if turbo_frame_request?
        render Design::Views::DocumentDesigns::PropertiesPanel.new(
          theme: @theme, paper_size: @paper_size, document_design: @document_design, editable: editable?)
      else
        redirect_to helpers.edit_theme_paper_size_document_design_path(@theme, @paper_size, @document_design)
      end
    end

    def editable?
      @theme.editable_by?(Design.current_user)
    end

    # Turbo-stream replacing the document preview with a freshly rendered one.
    def preview_frame_stream
      result = Design::PreviewService.new(@document_design, paper_size: @paper_size).generate
      component = if result[:success]
        Design::Views::DocumentDesigns::Preview.new(
          document_design: @document_design, paper_size: @paper_size,
          jpg_url: helpers.preview_jpg_theme_paper_size_document_design_path(@theme, @paper_size, @document_design, t: Time.now.to_i),
          overlay_data: result[:overlay_data], page_width: result[:page_width], page_height: result[:page_height],
          style_urls: build_style_urls)
      else
        Design::Views::DocumentDesigns::PreviewError.new(error: result[:error])
      end
      turbo_stream.replace("preview_frame", html: component.call.html_safe)
    end

    # Turbo-stream re-rendering the style panel after a save, pointed at where the
    # value now lives: an "apply to all" save → the theme base (level "theme", no
    # revert); otherwise → this document's override (level "document", revert shown).
    # Returns nil (no panel refresh) if the expected record isn't present.
    def saved_panel_stream(name, apply_scope)
      if apply_scope == "all"
        style = @theme.base_paragraph_styles.find_by(name: name)
        level = "theme"
      else
        style = @document_design.paragraph_styles.find_by(name: name)
        level = "document"
      end
      return nil unless style

      html = render_to_string(Design::Views::ParagraphStyles::Panel.new(
        paragraph_style: style,
        panel_update_url: helpers.panel_update_theme_paper_size_document_design_path(@theme, @paper_size, @document_design, level: level, style_id: style.id),
        back_url: helpers.edit_theme_paper_size_document_design_path(@theme, @paper_size, @document_design),
        revert_url: document_style_revert_url(style, level),
        editable: editable?,
        document_design: @document_design,
        save_scope_shadow_count: @theme.shadow_override_doc_types(name).size))
      turbo_stream.replace("properties_panel", html: html)
    end

    def render_paragraph_style_panel(style, panel_update_url:, revert_url:, status: :ok)
      # Back returns to the FULL edit page (tabs + preview), not the bare
      # properties_panel — and the link navigates _top, so reaching the panel via
      # a full-page preview-overlay click still lands back on the complete view.
      back_url = helpers.edit_theme_paper_size_document_design_path(@theme, @paper_size, @document_design)
      render Design::Views::ParagraphStyles::Panel.new(
        paragraph_style: style,
        panel_update_url: panel_update_url,
        back_url: back_url,
        revert_url: revert_url,
        editable: editable?,
        document_design: @document_design,
        save_scope_shadow_count: @theme.shadow_override_doc_types(style.name).size
      ), status: status
    end

    # Revert ("기본값으로 되돌리기") targets THIS document's override of the style. It's
    # available whenever such an override exists — when editing the override directly
    # (level "document"), and also when editing the inherited base style if a
    # same-name override already exists on this document (e.g. one a default-scope
    # save just created). Pure base styles with no override have nothing to revert.
    def document_style_revert_url(style, level)
      override = level == "document" ? style : @document_design.paragraph_styles.find_by(name: style.name)
      return nil unless override
      helpers.revert_theme_paper_size_document_design_paragraph_style_path(@theme, @paper_size, @document_design, override)
    end

    def find_panel_style(level, id)
      case level
      when "theme"    then @theme.base_paragraph_styles.find(id)
      when "paper"    then @paper_size.paragraph_styles.find(id)
      when "document" then @document_design.paragraph_styles.find(id)
      else raise ActiveRecord::RecordNotFound
      end
    end

    def build_preview_design
      dd = @document_design.dup
      dd.id = @document_design.id
      permitted = document_design_params
      he_attrs = permitted.delete(:heading_elements_attributes)
      dd.assign_attributes(permitted)
      elements = if he_attrs.present?
        he_attrs.values.reject { |h| h["_destroy"] == "1" }.map do |attrs|
          Design::HeadingElement.new(attrs.except("id", "_destroy"))
        end
      else
        @document_design.heading_elements.map(&:dup)
      end
      # In-memory ONLY — NOT `dd.heading_elements = elements` (the collection setter destroys real rows via dependent: :destroy).
      dd.association(:heading_elements).target = elements
      dd
    end

    def build_style_urls
      urls = {}
      @theme.base_paragraph_styles.each do |s|
        urls[s.name] = helpers.panel_theme_paper_size_document_design_path(@theme, @paper_size, @document_design, level: "theme", style_id: s.id)
      end
      @paper_size.paragraph_styles.each do |s|
        urls[s.name] = helpers.panel_theme_paper_size_document_design_path(@theme, @paper_size, @document_design, level: "paper", style_id: s.id)
      end
      @document_design.paragraph_styles.each do |s|
        urls[s.name] = helpers.panel_theme_paper_size_document_design_path(@theme, @paper_size, @document_design, level: "document", style_id: s.id)
      end
      urls
    end

    def document_design_params
      params.require(:document_design).permit(
        :heading_height_in_lines, :heading_v_align, :body_line_count,
        :toc_v_align,
        :column_count, :gutter,
        :has_header, :has_footer,
        :header_left_content_string, :header_right_content_string,
        :footer_left_content_string, :footer_right_content_string,
        :header_left_y_offset, :header_right_y_offset,
        :footer_left_y_offset, :footer_right_y_offset,
        :show_header_footer_on_first_page,
        :heading_bg_type, :heading_bg_color, :heading_bg_image,
        :heading_bg_gradient_start, :heading_bg_gradient_end, :heading_bg_gradient_angle,
        :text_box_anchor_position, :text_box_grid_width, :text_box_grid_height,
        :page_bg_color, :has_document_cover, :cover_type,
        heading_elements_attributes: [ :id, :element_type, :style_name, :position, :_destroy ]
      )
    end
  end
end
