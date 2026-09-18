module Design
  module Views
    module DocumentDesigns
      class Preview < Design::Views::Base
        register_element :turbo_frame

        # pages: [ { jpg_url:, overlay_data: }, ... ] in page order. mode: :scroll stacks
        # them all (the design editor); :single shows page 1 (style edit pages). The
        # legacy jpg_url/overlay_data kwargs are a one-page shorthand. print_mode: the
        # pages were rendered in print mode (the service result), so the guides
        # draw the binding.
        def initialize(document_design:, paper_size:, pages: nil, mode: :scroll, jpg_url: nil, overlay_data: [],
                       page_width: nil, page_height: nil, style_urls: {}, print_mode: false)
          @dd = document_design
          @ps = paper_size
          @pages = pages || (jpg_url ? [ { jpg_url: jpg_url, overlay_data: overlay_data || [] } ] : [])
          @pages = @pages.first(1) if mode == :single
          @page_width = page_width || @ps.width_pt
          @page_height = page_height || @ps.height_pt
          @style_urls = style_urls || {}
          @print_mode = print_mode
        end

        def view_template
          turbo_frame(id: "preview_frame") do
            if @pages.any?
              div(class: "flex flex-col items-center gap-4") do
                @pages.each_with_index { |page, i| render_page(page, i + 1) }
              end
            else
              render_fallback_message
            end
          end
        end

        private

        DISPLAY_WIDTH = 500

        def render_page(page, number)
          aspect = @page_width / @page_height
          div(class: "flex flex-col items-center gap-1") do
            div(class: "relative bg-white shadow-lg", style: "width: #{DISPLAY_WIDTH}px; aspect-ratio: #{aspect};",
                data: guide_data(number)) do
              img(src: page[:jpg_url], class: "absolute inset-0 w-full h-full object-contain",
                  style: "pointer-events: none;", alt: "Preview of #{@dd.doc_type} page #{number}", loading: "eager")
              if guides?
                div(class: "pointer-events-none absolute inset-0 group-data-[guides=off]/preview:hidden",
                    data: { "design--page-guides-target": "layer" })
              end
              render_svg_overlay(page[:overlay_data]) if page[:overlay_data].present?
            end
            if @pages.size > 1
              p(class: "text-xs text-slate-500", data: { page_label: true }) { "#{number} / #{@pages.size}" }
            end
          end
        end

        def guides? = @dd.guide_kind != :none

        def guide_data(number)
          return {} unless guides?
          { controller: "design--page-guides", action: "turbo:morph-element->design--page-guides#draw",
            "design--page-guides-geometry-value": guide_geometry(number).to_json }
        end

        # The page-guides controller's input, in pt: the rendered page size (a
        # wing's flap width comes from the service result), the paper size's
        # margins, the binding only when this preview renders in print mode,
        # this design's columns, and the page's parity (preview page N is odd
        # when N is, as the engine's start_page 0 makes it).
        def guide_geometry(number)
          { kind: @dd.guide_kind.to_s, width: @page_width.to_f.round(3), height: @page_height.to_f.round(3),
            top: @ps.top_margin_pt.to_f.round(3), bottom: @ps.bottom_margin_pt.to_f.round(3),
            left: @ps.left_margin_pt.to_f.round(3), right: @ps.right_margin_pt.to_f.round(3),
            binding: @print_mode ? @ps.binding_margin_pt.to_f.round(3) : 0.0,
            columnCount: @dd.column_count.to_i, gutter: @dd.gutter.to_f, parity: number.odd? ? "odd" : "even" }
        end

        def render_svg_overlay(overlay_data)
          div(class: "absolute inset-0") do
            render OverlaySvg.new(overlay_data: overlay_data, page_width: @page_width, page_height: @page_height, style_urls: @style_urls)
          end
        end

        class OverlaySvg < Phlex::SVG
          def heading_labels
            {
              "title" => I18n.t("design.preview.overlay.title"),
              "subtitle" => I18n.t("design.preview.overlay.subtitle"),
              "author" => I18n.t("design.preview.overlay.author"),
              "publisher" => I18n.t("design.preview.overlay.publisher")
            }
          end

          def initialize(overlay_data:, page_width:, page_height:, style_urls: {})
            @overlay_data = overlay_data
            @page_width = page_width
            @page_height = page_height
            @style_urls = style_urls || {}
          end

          OVERLAY_CSS = <<~CSS.freeze
            .overlay-zone rect { fill: transparent; stroke: transparent; }
            .overlay-zone text { fill: transparent; }
            .overlay-zone:hover rect, .overlay-zone.selected rect { fill: rgba(245, 158, 11, 0.12); stroke: #f59e0b; }
            .overlay-zone:hover text, .overlay-zone.selected text { fill: #92400e; }
            .overlay-zone.selected rect { stroke-width: 2; }
            .para-zone rect { fill: transparent; stroke: transparent; }
            .para-zone text { fill: transparent; }
            .para-zone:hover rect, .para-zone.selected rect { fill: rgba(59, 130, 246, 0.1); stroke: #3b82f6; }
            .para-zone:hover text, .para-zone.selected text { fill: #1e40af; }
            .para-zone.selected rect { stroke-width: 1.5; }
          CSS

          def view_template
            svg(
              viewBox: "0 0 #{@page_width} #{@page_height}",
              class: "w-full h-full",
              xmlns: "http://www.w3.org/2000/svg"
            ) do
              style { plain OVERLAY_CSS }

              @overlay_data.each do |overlay|
                render_overlay(overlay)
              end
            end
          end

          private

          def render_overlay(overlay)
            type = overlay[:type]
            # Coordinates can arrive as strings (doc_processor_rb's block_overlays
            # columns, or a JSON-reloaded cache stamp); coerce so the SVG math
            # (e.g. width / 2.0) doesn't blow up on a String.
            overlay = overlay.merge(
              x: overlay[:x].to_f, y: overlay[:y].to_f,
              width: overlay[:width].to_f, height: overlay[:height].to_f
            )

            if type == "heading_area" || type&.start_with?("heading_")
              render_heading_overlay(overlay)
            elsif type == "paragraph"
              render_paragraph_overlay(overlay)
            elsif type == "toc_entry"
              render_toc_overlay(overlay)
            end
          end

          def render_heading_overlay(overlay)
            style_name = overlay[:markup]
            url = @style_urls[style_name]
            label = heading_labels[style_name] || style_name&.capitalize || I18n.t("design.preview.heading_fallback")

            wrapper(url, css_class: "overlay-zone") do
              rect(
                x: overlay[:x], y: overlay[:y],
                width: overlay[:width], height: overlay[:height],
                stroke_width: 1,
                stroke_dasharray: "6 3"
              )
              text(
                x: overlay[:x] + overlay[:width] / 2.0,
                y: overlay[:y] + overlay[:height] / 2.0,
                text_anchor: "middle",
                dominant_baseline: "central",
                font_size: 11,
                font_family: "system-ui, sans-serif"
              ) { label }
            end
          end

          def render_paragraph_overlay(overlay)
            style_name = overlay[:markup]
            url = @style_urls[style_name]
            label = style_name&.capitalize || I18n.t("design.preview.body_fallback")

            wrapper(url, css_class: "para-zone") do
              rect(
                x: overlay[:x], y: overlay[:y],
                width: overlay[:width], height: overlay[:height],
                stroke_width: 0.5,
                stroke_dasharray: "4 2"
              )
              text(
                x: overlay[:x] + 4,
                y: overlay[:y] + overlay[:height] / 2.0,
                dominant_baseline: "central",
                font_size: 9,
                font_family: "system-ui, sans-serif"
              ) { label }
            end
          end

          def render_toc_overlay(overlay)
            # Each TOC entry's markup is its per-level style (h2/h3/h4); link there
            # so clicking a chapter/section entry edits the right style.
            url = @style_urls[overlay[:markup]] || @style_urls["body"]
            label = overlay[:content_preview] || I18n.t("design.preview.toc_entry")

            wrapper(url, css_class: "para-zone") do
              rect(
                x: overlay[:x], y: overlay[:y],
                width: overlay[:width], height: overlay[:height],
                stroke_width: 0.5,
                stroke_dasharray: "4 2"
              )
              text(
                x: overlay[:x] + 4,
                y: overlay[:y] + overlay[:height] / 2.0,
                dominant_baseline: "central",
                font_size: 9,
                font_family: "system-ui, sans-serif"
              ) { label }
            end
          end

          def wrapper(url, css_class:, &block)
            if url
              # No href on the SVG anchor — Turbo's link handler throws on an SVG
              # anchor's href. The overlay-link controller navigates on click instead.
              a(class: css_class, style: "pointer-events: auto; cursor: pointer;",
                data: { controller: "design--overlay-link", "design--overlay-link-url-value": url,
                        action: "click->design--overlay-link#navigate" }, &block)
            else
              g(class: css_class, style: "pointer-events: auto; cursor: pointer;", &block)
            end
          end
        end

        def render_fallback_message
          div(class: "flex justify-center items-center p-12 text-slate-500") do
            p { I18n.t("design.preview.generating") }
          end
        end
      end
    end
  end
end
