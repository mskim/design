module Design
  # Preview rendering shared by the design editor and the style panel: the
  # preview frame (scroll or single page), its overlay links to style pages,
  # and the stream that refreshes it after a save.
  module DocumentDesignPreview
    extend ActiveSupport::Concern

    # 인쇄용: set by design--preview-toolbar in the browser (a per-browser view
    # setting, like 안내선); every preview render reads it.
    PRINT_COOKIE = "design_preview_print"

    private

    def print_preview? = cookies[PRINT_COOKIE] == "1"

    # The service for this request's preview (dd may be the live-preview copy,
    # rendered with live: true so it never touches the saved design's cache).
    def preview_service(dd = @document_design, live: false)
      Design::PreviewService.new(dd, paper_size: @paper_size, print_mode: print_preview?, live: live)
    end

    # Stale style link (a reverted style, or an old level/style_id link whose row
    # is gone): show the live document view instead of raising. A turbo-frame request re-renders the
    # properties panel in place, on the 단락정의 tab the style link came from; a
    # full navigation redirects to the editor.
    def fall_back_to_document_view
      if turbo_frame_request?
        render Design::Views::DocumentDesigns::PropertiesPanel.new(
          theme: @theme, paper_size: @paper_size, document_design: @document_design, editable: editable?,
          tab: "typography")
      else
        redirect_to helpers.edit_theme_paper_size_document_design_path(@theme, @paper_size, @document_design)
      end
    end

    def editable?
      @theme.editable_by?(Design.current_user)
    end

    # "single" (style edit pages) or nil → :scroll (the design editor). Carried on the
    # preview frame src and as the style panel form's preview-mode value.
    def preview_mode
      params[:preview_mode] == "single" ? :single : :scroll
    end

    # What the style panel should send back: "single" or nil (nothing for scroll).
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
        # print=1 so a browser never reuses a normal image for a print one (the
        # helper drops the nil param).
        { jpg_url: helpers.preview_jpg_theme_paper_size_document_design_path(
            @theme, @paper_size, @document_design, page: i + 1, t: stamp, print: ("1" if result[:print_mode]),
            live: result[:live_token]),
          overlay_data: pg[:overlay_data] }
      end
      Design::Views::DocumentDesigns::Preview.new(
        document_design: dd, paper_size: @paper_size, pages: pages, mode: preview_mode,
        page_width: result[:page_width], page_height: result[:page_height], style_urls: build_style_urls,
        print_mode: result[:print_mode] == true)
    end

    # Turbo-stream replacing the document preview with a freshly rendered one.
    def preview_frame_stream
      result = preview_service.generate
      turbo_stream.replace("preview_frame", html: preview_component(result).call.html_safe)
    end

    # Preview-overlay zones → the style's full-page editor (name-keyed; every
    # style the preview can show resolves through merged_paragraph_styles).
    def build_style_urls
      @document_design.merged_paragraph_styles.map(&:name).index_with do |name|
        helpers.theme_paper_size_document_design_style_path(@theme, @paper_size, @document_design, name)
      end
    end
  end
end
