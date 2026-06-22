module Design
  module Views
    module DocumentDesigns
      class PropertiesPanel < Design::Views::Base
        register_element :turbo_frame

        def initialize(theme:, paper_size:, document_design:, editable: true)
          @theme = theme
          @paper_size = paper_size
          @document_design = document_design
          @editable = editable
        end

        def view_template
          turbo_frame(id: "properties_panel") do
            div(class: "w-96 border-l flex flex-col max-h-screen") do
              render_header
              render_form_body
            end
          end
        end

        private

        def render_header
          div(class: "shrink-0 flex items-center gap-2 px-4 py-2.5 border-b bg-slate-50") do
            h2(class: "text-sm font-semibold") { @document_design.doc_type.tr("_", " ").titleize }
            span(class: "text-xs text-muted-foreground") { "Design Properties" }
          end
        end

        def render_form_body
          form(
            action: form_action_url,
            method: "post",
            enctype: "multipart/form-data",
            class: "flex-1 overflow-y-auto",
            data: {
              controller: "design--live-preview",
              "design--live-preview-preview-url-value": preview_url,
              action: "input->design--live-preview#scheduleUpdate change->design--live-preview#scheduleUpdate"
            }
          ) do
            input(type: "hidden", name: "_method", value: "patch")
            input(type: "hidden", name: "authenticity_token", value: csrf_token)

            div(class: "p-4 space-y-3") do
              render RubyUI::Tabs.new(default: "layout") do
                render RubyUI::TabsList.new(class: "w-full") do
                  render RubyUI::TabsTrigger.new(value: "layout") { "Layout" }
                  render RubyUI::TabsTrigger.new(value: "typography") { "Typography" }
                  render RubyUI::TabsTrigger.new(value: "header_footer") { "Header/Footer" }
                end

                render RubyUI::TabsContent.new(value: "layout") do
                  render_layout_tab
                end

                render RubyUI::TabsContent.new(value: "typography") do
                  render_typography_tab
                end

                render RubyUI::TabsContent.new(value: "header_footer") do
                  render_header_footer_tab
                end
              end

              if @editable
                div(class: "pt-2") do
                  button(
                    type: "submit",
                    class: "inline-flex w-full items-center justify-center rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-700"
                  ) { "Save" }
                end
              end
            end
          end
        end

        # --------------- Layout Tab ---------------

        def render_layout_tab
          div(class: "space-y-3 pt-2") do
            div(class: "grid grid-cols-1 gap-3 sm:grid-cols-2") do
              number_field("Heading Lines", :heading_height_in_lines)
              select_field("Heading V-Align", :heading_v_align, %w[center top bottom])
              number_field("Body Line Count", :body_line_count, placeholder: @paper_size.body_line_count)
              number_field("Columns", :column_count)
              number_field("Gutter (pt)", :gutter, step: "0.1")
            end
            heading_elements_section
            heading_background_section
            render_text_box_section
            render_page_bg_section
            render_document_cover_section
          end
        end

        ANCHOR_LABELS = {
          1 => "1 — Top Left", 2 => "2 — Top Center", 3 => "3 — Top Right",
          4 => "4 — Mid Left", 5 => "5 — Center",     6 => "6 — Mid Right",
          7 => "7 — Bottom Left", 8 => "8 — Bottom Center", 9 => "9 — Bottom Right"
        }.freeze

        def render_text_box_section
          div(class: "rounded border border-slate-200 p-3 space-y-3") do
            h3(class: "text-sm font-semibold text-slate-900") { "Text Box Position" }
            div do
              label(class: "block text-xs font-medium mb-0.5 text-slate-600") { "Anchor Position" }
              select(
                name: "document_design[text_box_anchor_position]",
                class: "w-full rounded border border-slate-300 bg-white px-2 py-1 text-sm",
                **disabled_attr
              ) do
                option(value: "", selected: @document_design.text_box_anchor_position.nil?) { "Default (Bottom Left)" }
                ANCHOR_LABELS.each do |val, label_text|
                  option(value: val.to_s, selected: @document_design.text_box_anchor_position == val) { label_text }
                end
              end
            end
            div(class: "grid grid-cols-2 gap-2") do
              div do
                label(class: "block text-xs font-medium mb-0.5 text-slate-600") { "Grid Width" }
                input(
                  type: "number",
                  name: "document_design[text_box_grid_width]",
                  value: field_value(@document_design.text_box_grid_width),
                  placeholder: "4", min: 1, max: 12,
                  class: "w-full rounded border border-slate-300 px-2 py-1 text-sm",
                  **disabled_attr
                )
              end
              div do
                label(class: "block text-xs font-medium mb-0.5 text-slate-600") { "Grid Height" }
                input(
                  type: "number",
                  name: "document_design[text_box_grid_height]",
                  value: field_value(@document_design.text_box_grid_height),
                  placeholder: "6", min: 1, max: 12,
                  class: "w-full rounded border border-slate-300 px-2 py-1 text-sm",
                  **disabled_attr
                )
              end
            end
          end
        end

        def render_page_bg_section
          div(class: "rounded border border-slate-200 p-3 space-y-3") do
            h3(class: "text-sm font-semibold text-slate-900") { "Page Background (Bleed)" }
            div(data: { controller: "design--color-field" }) do
              label(class: "block text-xs font-medium mb-1 text-slate-600") { "Background Color" }
              div(class: "flex gap-2 items-center") do
                input(
                  type: "color",
                  value: normalize_color(@document_design.page_bg_color || "#ffffff"),
                  class: "h-7 w-7 rounded border cursor-pointer p-0",
                  data: { "design--color-field-target": "picker", action: "input->design--color-field#pickerChanged" },
                  **disabled_attr
                )
                input(
                  type: "text",
                  name: "document_design[page_bg_color]",
                  value: @document_design.page_bg_color || "",
                  placeholder: "CMYK=0,0,0,20 or #cccccc",
                  class: "flex-1 rounded border border-slate-300 px-2 py-1 text-sm",
                  data: { "design--color-field-target": "text", action: "input->design--color-field#textChanged" },
                  **disabled_attr
                )
              end
              p(class: "text-xs text-slate-500 mt-1") { "Extends 3mm beyond trim for bleed. Leave blank for no background." }
            end
          end
        end

        def render_document_cover_section
          div(class: "rounded border border-slate-200 p-3 space-y-3",
              data: { controller: "design--toggle-visibility" }) do
            h3(class: "text-sm font-semibold text-slate-900") { "Document Cover" }
            label(class: "flex items-center gap-2 text-sm text-slate-700") do
              input(type: "hidden", name: "document_design[has_document_cover]", value: "0")
              input(
                type: "checkbox",
                name: "document_design[has_document_cover]",
                value: "1",
                checked: @document_design.has_document_cover?,
                class: "rounded border-slate-300",
                data: { action: "change->design--toggle-visibility#toggle" },
                **disabled_attr
              )
              plain "Has Document Cover"
            end
            div(
              class: @document_design.has_document_cover? ? "" : "hidden",
              data: { "design--toggle-visibility-target": "content" }
            ) do
              label(class: "block text-xs font-medium mb-0.5 text-slate-600") { "Cover Type" }
              select(
                name: "document_design[cover_type]",
                class: "w-full rounded border border-slate-300 bg-white px-2 py-1 text-sm",
                **disabled_attr
              ) do
                Design::DocumentDesign::COVER_TYPES.each do |ct|
                  option(value: ct, selected: @document_design.cover_type == ct) { ct.tr("_", " ").titleize }
                end
              end
            end
          end
        end

        # --------------- Typography Tab ---------------

        def render_typography_tab
          style_order = %w[title subtitle author publisher h2 h3 h4 h5 h6 body]
          override_by_name = @document_design.paragraph_styles.index_by(&:name)
          # Scope the list to the styles this doc_type actually uses (e.g. a TOC
          # doesn't show wing_*/cover_*/seneca_*). Always keep styles that already
          # have a per-size override so existing edits stay visible.
          relevant = @document_design.relevant_style_names
          merged = @document_design.merged_paragraph_styles.select { |s|
            relevant.include?(s.name) || override_by_name.key?(s.name)
          }.sort_by { |s|
            idx = style_order.index(s.name)
            idx ? [ 0, idx ] : [ 1, s.name ]
          }

          div(class: "space-y-3 pt-4") do
            merged.each do |style|
              override = override_by_name[style.name]
              is_base = override.nil?

              div(class: "flex items-center justify-between py-1.5 border-b") do
                div do
                  span(class: "text-sm font-medium") { style.name }
                  if style.korean_name.present?
                    span(class: "text-xs text-slate-500 ml-2") { style.korean_name }
                  end
                  if is_base
                    span(class: "text-[10px] text-slate-400 ml-1") { "(base)" }
                  end
                end

                if @editable
                  if override
                    a(
                      href: typography_panel_url(override),
                      data: { turbo_frame: "properties_panel" },
                      class: "text-xs text-blue-600 hover:underline"
                    ) { "Edit" }
                  else
                    a(
                      href: typography_override_url(style.name),
                      data: { turbo_method: "post", turbo_frame: "properties_panel" },
                      class: "text-xs text-blue-600 hover:underline"
                    ) { "Edit" }
                  end
                end
              end
            end

            if @editable
              a(href: typography_new_style_url, data: { turbo_frame: "properties_panel" }) do
                render RubyUI::Button.new(variant: :outline, size: :sm, class: "w-full mt-2") { "Add Style" }
              end
            end
          end
        end

        def typography_panel_url(override)
          helpers.panel_theme_paper_size_document_design_path(
            @theme, @paper_size, @document_design,
            level: "document", style_id: override.id
          )
        end

        def typography_override_url(style_name)
          helpers.override_theme_paper_size_document_design_paragraph_styles_path(
            @theme, @paper_size, @document_design,
            name: style_name
          )
        end

        def typography_new_style_url
          helpers.new_theme_paper_size_document_design_paragraph_style_path(
            @theme, @paper_size, @document_design
          )
        end

        # --------------- Header/Footer Tab ---------------

        def render_header_footer_tab
          div(class: "space-y-4 pt-2") do
            header_footer_section
          end
        end

        # --------------- Existing engine sections (ported from FormPanel) ---------------

        def heading_elements_section
          h2(class: "text-lg font-medium text-slate-900") { "Heading Elements" }
          div(class: "rounded border border-slate-200 p-3 flex flex-col gap-2",
              data: { controller: "design--heading-elements" }) do
            div(data: { "design--heading-elements-target": "list" }) do
              @document_design.heading_elements.to_a.each_with_index { |el, idx| heading_element_row(el, idx) }
            end
            div(class: "flex gap-2 mt-2") do
              select(
                class: "flex-1 rounded border border-slate-300 px-2 py-1.5 text-sm",
                data: { "design--heading-elements-target": "typeSelect" },
                **disabled_attr
              ) do
                Design::HeadingElement::ELEMENT_TYPES.each { |etype| option(value: etype) { etype.capitalize } }
              end
              unless @editable
                button(
                  type: "button",
                  class: "px-3 py-1.5 text-xs font-medium rounded bg-slate-100 border border-slate-300 opacity-50 cursor-not-allowed",
                  disabled: true
                ) { "+ Add" }
              else
                button(
                  type: "button",
                  class: "px-3 py-1.5 text-xs font-medium rounded bg-slate-100 border border-slate-300 hover:bg-slate-200",
                  data: { action: "design--heading-elements#add" }
                ) { "+ Add" }
              end
            end
            div(hidden: true, data: { "design--heading-elements-target": "template" }) { heading_element_row(nil, "IDX") }
          end
        end

        def heading_element_row(el, idx)
          prefix = "document_design[heading_elements_attributes][#{idx}]"
          div(class: "flex items-center gap-2 py-1.5 border-b border-slate-200 group",
              data: { "design--heading-elements-target": "row" }) do
            span(class: "cursor-grab text-slate-400",
                 data: { action: "mousedown->design--heading-elements#dragStart" }) { "☰" }
            span(class: "text-sm font-medium w-20") { (el&.element_type || "title").capitalize }
            input(type: "hidden", name: "#{prefix}[id]", value: el.id.to_s) if el&.persisted?
            input(type: "hidden", name: "#{prefix}[element_type]", value: el&.element_type || "title",
                  data: { "design--heading-elements-target": "elementType" })
            input(type: "hidden", name: "#{prefix}[position]", value: idx.to_s,
                  data: { "design--heading-elements-target": "position" })
            input(type: "hidden", name: "#{prefix}[_destroy]", value: "0",
                  data: { "design--heading-elements-target": "destroy" })
            span(class: "text-xs text-slate-400") { "→" }
            input(
              type: "text",
              name: "#{prefix}[style_name]",
              value: el&.style_name || "title",
              placeholder: "style name",
              class: "flex-1 rounded border border-slate-300 px-2 py-1 text-xs",
              data: { "design--heading-elements-target": "styleName" },
              **disabled_attr
            )
            button(
              type: "button",
              class: "text-red-400 hover:text-red-600 opacity-0 group-hover:opacity-100 transition-opacity",
              data: @editable ? { action: "design--heading-elements#remove" } : {},
              **disabled_attr
            ) { "✕" }
          end
        end

        def heading_background_section
          h2(class: "text-lg font-medium text-slate-900") { "Heading Background" }
          current = @document_design.heading_bg_type || "color"
          div(class: "rounded border border-slate-200 p-3 flex flex-col gap-3",
              data: { controller: "design--heading-bg" }) do
            div(class: "flex gap-3") do
              %w[color image gradient].each do |bg_type|
                label(class: "flex items-center gap-1 text-xs cursor-pointer") do
                  input(
                    type: "radio",
                    name: "document_design[heading_bg_type]",
                    value: bg_type,
                    checked: current == bg_type,
                    data: { action: "design--heading-bg#typeChanged", "design--heading-bg-target": "typeRadio" },
                    **disabled_attr
                  )
                  plain bg_type.capitalize
                end
              end
            end
            div(class: current == "color" ? "" : "hidden",
                data: { "design--heading-bg-target": "colorFields" }) do
              label(class: "block text-xs font-medium mb-1 text-slate-600") { "Color" }
              div(class: "flex items-center gap-1", data: { controller: "design--color-mode-field" }) do
                input(
                  type: "color",
                  data: { "design--color-mode-field-target": "picker", action: "input->design--color-mode-field#pickerChanged" },
                  class: "h-7 w-7 cursor-pointer border-0 p-0",
                  **disabled_attr
                )
                select(
                  data: { "design--color-mode-field-target": "mode", action: "change->design--color-mode-field#modeChanged" },
                  class: "text-xs px-1 py-0.5",
                  **disabled_attr
                ) do
                  option(value: "cmyk") { "CMYK" }
                  option(value: "hex") { "Hex" }
                  option(value: "named") { "Name" }
                end
                input(
                  type: "text",
                  name: "document_design[heading_bg_color]",
                  value: @document_design.heading_bg_color || "white",
                  data: { "design--color-mode-field-target": "input", action: "input->design--color-mode-field#textChanged" },
                  class: "flex-1 border border-slate-300 rounded px-2 py-1 text-sm",
                  **disabled_attr
                )
              end
            end
            div(class: current == "image" ? "" : "hidden",
                data: { "design--heading-bg-target": "imageFields" }) do
              label(class: "block text-xs font-medium mb-1 text-slate-600") { "Image" }
              input(type: "file", name: "document_design[heading_bg_image]", accept: "image/*",
                    class: "w-full text-xs", **disabled_attr)
              if @document_design.heading_bg_image.attached?
                p(class: "text-xs text-slate-500 mt-1") { "Current: #{@document_design.heading_bg_image.filename}" }
              end
            end
            div(class: current == "gradient" ? "" : "hidden",
                data: { "design--heading-bg-target": "gradientFields" }) do
              div(class: "grid grid-cols-2 gap-2") do
                div do
                  label(class: "block text-xs font-medium mb-1 text-slate-600") { "Start" }
                  input(type: "color", name: "document_design[heading_bg_gradient_start]",
                        value: @document_design.heading_bg_gradient_start || "#ffffff",
                        class: "w-full h-8 rounded border cursor-pointer", **disabled_attr)
                end
                div do
                  label(class: "block text-xs font-medium mb-1 text-slate-600") { "End" }
                  input(type: "color", name: "document_design[heading_bg_gradient_end]",
                        value: @document_design.heading_bg_gradient_end || "#000000",
                        class: "w-full h-8 rounded border cursor-pointer", **disabled_attr)
                end
              end
              div do
                label(class: "block text-xs font-medium mb-1 text-slate-600") { "Angle (degrees)" }
                input(type: "number", name: "document_design[heading_bg_gradient_angle]",
                      value: (@document_design.heading_bg_gradient_angle || 0).to_s,
                      min: 0, max: 360, step: 1,
                      class: "w-full rounded border border-slate-300 px-2 py-1.5 text-sm",
                      **disabled_attr)
              end
            end
          end
        end

        def header_footer_section
          h2(class: "text-lg font-medium text-slate-900") { "Header / Footer" }
          div(class: "flex flex-wrap gap-4") do
            checkbox_field("Header", :has_header)
            checkbox_field("Footer", :has_footer)
            checkbox_field("Show on first page", :show_header_footer_on_first_page)
          end
          div(class: "grid grid-cols-1 gap-3 sm:grid-cols-2") do
            text_field("Header Left", :header_left_content_string)
            text_field("Header Right", :header_right_content_string)
            text_field("Footer Left", :footer_left_content_string)
            text_field("Footer Right", :footer_right_content_string)
          end
        end

        # --------------- Field helpers (ported from FormPanel, extended with disabled support) ---------------

        def number_field(label_text, attr, step: nil, placeholder: nil)
          field_row(label_text) do
            # type=text (not number): the native spinner arrows ate the whole field
            # in the narrow panel and hid the value. inputmode=decimal still gives a
            # numeric keyboard on touch devices; Rails coerces the string on save.
            attrs = {
              type: "text",
              inputmode: "decimal",
              name: "document_design[#{attr}]",
              value: field_value(@document_design.public_send(attr)),
              class: "border border-slate-300 rounded px-2 py-1 text-sm w-full"
            }
            attrs[:placeholder] = field_value(placeholder) if placeholder
            attrs.merge!(disabled_attr)
            input(**attrs)
          end
        end

        def text_field(label_text, attr)
          field_row(label_text) do
            input(
              type: "text",
              name: "document_design[#{attr}]",
              value: field_value(@document_design.public_send(attr)),
              class: "border border-slate-300 rounded px-2 py-1 text-sm w-full",
              **disabled_attr
            )
          end
        end

        def select_field(label_text, attr, options)
          field_row(label_text) do
            select(
              name: "document_design[#{attr}]",
              class: "border border-slate-300 rounded px-2 py-1 text-sm w-full",
              **disabled_attr
            ) do
              current = @document_design.public_send(attr)
              options.each do |opt|
                option(value: opt, selected: opt == current) { opt }
              end
            end
          end
        end

        def checkbox_field(label_text, attr)
          label(class: "flex items-center gap-2 text-sm text-slate-700") do
            input(type: "hidden", name: "document_design[#{attr}]", value: "0")
            input(
              type: "checkbox",
              name: "document_design[#{attr}]",
              value: "1",
              checked: @document_design.public_send(attr),
              **disabled_attr
            )
            plain label_text
          end
        end

        def field_row(label_text, &block)
          # Stack the label above the input: the properties panel is narrow (~28rem),
          # so a side-by-side label left no room for the value (only the spinner showed).
          div(class: "flex flex-col gap-1") do
            label(class: "text-sm text-slate-600") { label_text }
            yield
          end
        end

        def field_value(value)
          case value
          when nil then nil
          when BigDecimal then value.to_s("F")
          else value.to_s
          end
        end

        def normalize_color(color)
          return "#ffffff" if color.nil? || color.to_s.strip.empty? || color == "white"
          return "#000000" if color == "black"
          return color if color.start_with?("#")

          if color.start_with?("CMYK=")
            parts = color.sub("CMYK=", "").split(",").map(&:to_f)
            if parts.length == 4
              c, m, y, k = parts.map { |v| v / 100.0 }
              r = ((1 - c) * (1 - k) * 255).round
              g = ((1 - m) * (1 - k) * 255).round
              b = ((1 - y) * (1 - k) * 255).round
              return "#%02x%02x%02x" % [ r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255) ]
            end
          end

          "#ffffff"
        end

        def disabled_attr
          @editable ? {} : { disabled: true }
        end

        # URL helpers — isolated so tests can override with define_singleton_method stubs
        def form_action_url
          helpers.theme_paper_size_document_design_path(@theme, @paper_size, @document_design)
        end

        def preview_url
          helpers.preview_theme_paper_size_document_design_path(@theme, @paper_size, @document_design)
        end

        def csrf_token
          helpers.form_authenticity_token
        end
      end
    end
  end
end
