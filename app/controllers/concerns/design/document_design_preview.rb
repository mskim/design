module Design
  # Preview rendering shared by the design editor and the style panel: the
  # preview frame (scroll or single page), its overlay links to style pages,
  # and the stream that refreshes it after a save.
  module DocumentDesignPreview
    extend ActiveSupport::Concern

    private

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

    # "single" (style edit pages) or nil → :scroll (the design editor). Carried on the
    # preview frame src and as a hidden field in the style Panel form.
    def preview_mode
      params[:preview_mode] == "single" ? :single : :scroll
    end

    # What the style Panel form should post back: "single" or nil (nothing for scroll).
    def panel_preview_mode
      preview_mode == :single ? "single" : nil
    end

    # Older/stubbed service results carry only the page-1 keys; normalise to pages.
    def preview_pages(result)
      result[:pages] || [ { jpg_path: result[:jpg_path], overlay_data: result[:overlay_data] || [] } ]
    end

    # Preview (or PreviewError) component for a service result.
    # dd may be an unsaved live-preview copy (same id); URLs always use @document_design.
    def preview_component(result, dd = @document_design)
      return Design::Views::DocumentDesigns::PreviewError.new(error: result[:error]) unless result[:success]

      stamp = Time.now.to_i
      pages = preview_pages(result).each_with_index.map do |pg, i|
        { jpg_url: helpers.preview_jpg_theme_paper_size_document_design_path(@theme, @paper_size, @document_design, page: i + 1, t: stamp),
          overlay_data: pg[:overlay_data] }
      end
      Design::Views::DocumentDesigns::Preview.new(
        document_design: dd, paper_size: @paper_size, pages: pages, mode: preview_mode,
        page_width: result[:page_width], page_height: result[:page_height], style_urls: build_style_urls)
    end

    # Turbo-stream replacing the document preview with a freshly rendered one.
    def preview_frame_stream
      result = Design::PreviewService.new(@document_design, paper_size: @paper_size).generate
      turbo_stream.replace("preview_frame", html: preview_component(result).call.html_safe)
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
  end
end
