module Design
  module DocumentDesignEditing
    extend ActiveSupport::Concern

    include Design::DocumentDesignPreview

    def preview
      dd = request.post? ? build_preview_design : @document_design
      result = preview_service(dd).generate
      component = preview_component(result, dd)

      if request.post?
        render turbo_stream: turbo_stream.replace("preview_frame", html: component.call.html_safe)
      else
        render component
      end
    end

    # print=1 comes from the frame's URLs (the cookie at render time); the
    # theme page's cards and design_preview_img call this without it and must
    # stay normal, so the cookie is not read here.
    def preview_jpg
      result = Design::PreviewService.new(@document_design, paper_size: @paper_size, print_mode: params[:print] == "1").generate
      page = params.fetch(:page, 1).to_i
      path = preview_pages(result)[page - 1]&.dig(:jpg_path) if result[:success] && page >= 1
      if path && File.exist?(path)
        send_file path, type: "image/jpeg", disposition: "inline"
      else
        head :not_found
      end
    end

    def properties_panel
      render Design::Views::DocumentDesigns::PropertiesPanel.new(theme: @theme, paper_size: @paper_size, document_design: @document_design, editable: editable?, tab: params[:tab])
    end

    # Old style links (panel?level=…&style_id=…, pre-D2b bookmarks and
    # preview pages): styles are keyed by name now. A row that is gone falls
    # back to the document view; an unknown level is a malformed link (404).
    def panel
      return head(:not_found) unless KNOWN_STYLE_LEVELS.include?(params[:level])
      style = find_panel_style(params[:level], params[:style_id])
      redirect_to helpers.theme_paper_size_document_design_style_path(
        @theme, @paper_size, @document_design, style.name, preview_mode: params[:preview_mode].presence)
    rescue ActiveRecord::RecordNotFound
      fall_back_to_document_view
    end

    private

    KNOWN_STYLE_LEVELS = %w[theme paper document].freeze

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

    def document_design_params
      params.require(:document_design).permit(
        :heading_height_in_lines, :heading_v_align,
        :toc_v_align,
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
        :image_opacity, :logo_width, :logo_height, :logo_position, :logo_offset,
        :photo_grid_width, :photo_grid_height, :photo_anchor, :photo_fit,
        :photo_border_width, :photo_border_color,
        heading_elements_attributes: [ :id, :element_type, :style_name, :position, :_destroy ]
      )
    end
  end
end
