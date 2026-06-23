module Design
  module DocumentDesignEditing
    extend ActiveSupport::Concern

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
      render_paragraph_style_panel(
        style,
        panel_update_url: helpers.panel_update_theme_paper_size_document_design_path(@theme, @paper_size, @document_design, level: params[:level], style_id: style.id),
        revert_url: document_style_revert_url(style, params[:level]))
    end

    def panel_update
      style = find_panel_style(params[:level], params[:style_id])
      if style.update(paragraph_style_params)
        Design::ThemeDbExportService.new(@theme).export!
        result = Design::PreviewService.new(@document_design, paper_size: @paper_size).generate
        preview = if result[:success]
          Design::Views::DocumentDesigns::Preview.new(
            document_design: @document_design, paper_size: @paper_size,
            jpg_url: helpers.preview_jpg_theme_paper_size_document_design_path(@theme, @paper_size, @document_design, t: Time.now.to_i),
            overlay_data: result[:overlay_data], page_width: result[:page_width], page_height: result[:page_height],
            style_urls: build_style_urls)
        else
          Design::Views::DocumentDesigns::PreviewError.new(error: result[:error])
        end
        render turbo_stream: turbo_stream.replace("preview_frame", html: preview.call.html_safe)
      else
        render_paragraph_style_panel(
          style,
          panel_update_url: helpers.panel_update_theme_paper_size_document_design_path(@theme, @paper_size, @document_design, level: params[:level], style_id: style.id),
          revert_url: document_style_revert_url(style, params[:level]),
          status: :unprocessable_entity)
      end
    end

    private

    def editable?
      @theme.editable_by?(Design.current_user)
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
        editable: editable?
      ), status: status
    end

    # Returns the revert URL for document-level override styles only;
    # theme- and paper-level styles are base records and cannot be reverted.
    def document_style_revert_url(style, level)
      return nil unless level == "document"
      helpers.revert_theme_paper_size_document_design_paragraph_style_path(@theme, @paper_size, @document_design, style)
    end

    def find_panel_style(level, id)
      case level
      when "theme"    then @theme.base_paragraph_styles.find(id)
      when "paper"    then @paper_size.paragraph_styles.find(id)
      when "document" then @document_design.paragraph_styles.find(id)
      else raise ActiveRecord::RecordNotFound
      end
    end

    def paragraph_style_params
      params.require(:paragraph_style).permit(
        :name, :korean_name, :font, :font_size, :scale,
        :text_color, :text_align, :tracking, :space_width, :text_line_spacing,
        :first_line_indent, :left_indent, :right_indent,
        :space_before, :space_after, :space_before_in_lines, :space_after_in_lines,
        :bold_font, :bold_text_color, :emphasis_font, :emphasis_color,
        :fill_type, :fill_color, :fill_ending_color, :fill_gradient_direction,
        :border_thickness, :border_color, :border_side, :rounded_corners, :corner_radius,
        :padding_top, :padding_bottom)
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
