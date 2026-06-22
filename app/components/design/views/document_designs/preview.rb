module Design
  module Views
    module DocumentDesigns
      class Preview < Design::Views::Base
        register_element :turbo_frame

        def initialize(document_design:, paper_size:, jpg_url: nil, overlay_data: [], page_width: nil, page_height: nil, style_urls: {})
          @dd = document_design
          @ps = paper_size
          @jpg_url = jpg_url
          @overlay_data = overlay_data || []
          @page_width = page_width || @ps.width_pt
          @page_height = page_height || @ps.height_pt
          @style_urls = style_urls || {}
        end

        def view_template
          turbo_frame(id: "preview_frame") do
            if @jpg_url
              render_jpg_preview
            else
              render_fallback_message
            end
          end
        end

        private

        def render_jpg_preview
          aspect = @page_width / @page_height
          display_width = 500

          div(class: "flex justify-center items-start") do
            div(
              class: "relative bg-white shadow-lg",
              style: "width: #{display_width}px; aspect-ratio: #{aspect};"
            ) do
              img(
                src: @jpg_url,
                class: "absolute inset-0 w-full h-full object-contain",
                style: "pointer-events: none;",
                alt: "Preview of #{@dd.doc_type}",
                loading: "eager"
              )

              render_svg_overlay if @overlay_data.any?
            end
          end
        end

        def render_svg_overlay
          div(class: "absolute inset-0") do
            render OverlaySvg.new(
              overlay_data: @overlay_data,
              page_width: @page_width,
              page_height: @page_height,
              style_urls: @style_urls
            )
          end
        end

        class OverlaySvg < Phlex::SVG
          HEADING_LABELS = {
            "title" => "Title",
            "subtitle" => "Subtitle",
            "author" => "Author",
            "publisher" => "Publisher"
          }.freeze

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
            label = HEADING_LABELS[style_name] || style_name&.capitalize || "Heading"

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
            label = style_name&.capitalize || "Body"

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
            # TOC entries use "toc" as markup; link to the "body" style (which TOC renderer uses)
            url = @style_urls["toc"] || @style_urls["body"]
            label = overlay[:content_preview] || "TOC Entry"

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
              a(href: url, class: css_class, style: "pointer-events: auto; cursor: pointer;", data: { turbo_frame: "properties_panel" }, &block)
            else
              g(class: css_class, style: "pointer-events: auto; cursor: pointer;", &block)
            end
          end
        end

        def render_fallback_message
          div(class: "flex justify-center items-center p-12 text-slate-500") do
            p { "Generating preview..." }
          end
        end
      end
    end
  end
end
