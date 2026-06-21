module Design
  module Views
    module ParagraphStyles
      class Fields < Design::Views::Base
        def initialize(paragraph_style:, editable: true)
          @paragraph_style = paragraph_style
          @editable = editable
        end

        def view_template
          identity_section
          font_section
          text_section
          bold_emphasis_section
          spacing_section
          fill_section
          border_section
          padding_section
        end

        private

        # ── Identity ──
        def identity_section
          h2(class: "text-lg font-medium text-slate-900") { "Identity" }
          div(class: "grid grid-cols-1 gap-3 sm:grid-cols-2") do
            text_field("Name", :name)
            text_field("Korean Name", :korean_name)
          end
        end

        # ── Font ──
        def font_section
          h2(class: "text-lg font-medium text-slate-900") { "Font" }
          div(class: "grid grid-cols-1 gap-3 sm:grid-cols-3") do
            font_select("Font", :font)
            number_field("Size (pt)", :font_size, step: "0.1")
            number_field("Scale", :scale, step: "0.01")
          end
        end

        # ── Text ──
        def text_section
          h2(class: "text-lg font-medium text-slate-900") { "Text" }
          div(class: "grid grid-cols-1 gap-3 sm:grid-cols-2") do
            color_row("Color", :text_color)
            select_field("Align", :text_align, %w[left center right justify], include_blank: "— inherit —")
            number_field("Tracking", :tracking, step: "0.1")
            number_field("Space Width", :space_width, step: "0.1")
            number_field("Line Spacing", :text_line_spacing, step: "0.1")
          end
        end

        # ── Bold & Emphasis ──
        def bold_emphasis_section
          h2(class: "text-lg font-medium text-slate-900") { "Bold & Emphasis" }
          div(class: "grid grid-cols-1 gap-3 sm:grid-cols-2") do
            font_select("Bold Font", :bold_font)
            color_row("Bold Color", :bold_text_color)
            font_select("Emphasis Font", :emphasis_font)
            color_row("Emphasis Color", :emphasis_color)
          end
        end

        # ── Spacing ──
        def spacing_section
          h2(class: "text-lg font-medium text-slate-900") { "Spacing" }
          div(class: "grid grid-cols-1 gap-3 sm:grid-cols-2") do
            number_field("First Line Indent", :first_line_indent, step: "0.1")
            number_field("Left Indent", :left_indent, step: "0.1")
            number_field("Right Indent", :right_indent, step: "0.1")
            number_field("Space Before (pt)", :space_before, step: "0.1")
            number_field("Space After (pt)", :space_after, step: "0.1")
            number_field("Space Before (lines)", :space_before_in_lines, step: "0.1")
            number_field("Space After (lines)", :space_after_in_lines, step: "0.1")
          end
        end

        # ── Fill ──
        def fill_section
          h2(class: "text-lg font-medium text-slate-900") { "Fill" }
          div(class: "grid grid-cols-1 gap-3 sm:grid-cols-2") do
            select_field("Fill Type", :fill_type, %w[none solid gradient])
            select_field("Gradient Dir.", :fill_gradient_direction, %w[horizontal vertical diagonal], include_blank: "— none —")
            color_row("Fill Color", :fill_color)
            color_row("Ending Color", :fill_ending_color)
          end
        end

        # ── Border ──
        def border_section
          h2(class: "text-lg font-medium text-slate-900") { "Border" }
          div(class: "grid grid-cols-1 gap-3 sm:grid-cols-2") do
            number_field("Thickness (pt)", :border_thickness, step: "0.1")
            color_row("Border Color", :border_color)
          end

          div(class: "grid grid-cols-1 gap-4 sm:grid-cols-2 mt-2") do
            border_side_editor
            corner_editor
          end
        end

        # ── Padding ──
        def padding_section
          h2(class: "text-lg font-medium text-slate-900") { "Padding" }
          div(class: "grid grid-cols-1 gap-3 sm:grid-cols-2") do
            number_field("Padding Top (pt)", :padding_top, step: "0.1")
            number_field("Padding Bottom (pt)", :padding_bottom, step: "0.1")
          end
        end

        # ── Field helpers ──

        def field_row(label_text, &block)
          div(class: "flex items-center gap-3") do
            label(class: "text-sm text-slate-600 w-36 shrink-0") { label_text }
            yield
          end
        end

        def text_field(label_text, attr)
          field_row(label_text) do
            input(
              type: "text",
              name: "paragraph_style[#{attr}]",
              value: field_value(@paragraph_style.public_send(attr)),
              class: "border border-slate-300 rounded px-2 py-1 text-sm w-full",
              **disabled_attr
            )
          end
        end

        def number_field(label_text, attr, step: nil)
          field_row(label_text) do
            attrs = {
              type: "number",
              name: "paragraph_style[#{attr}]",
              value: field_value(@paragraph_style.public_send(attr)),
              class: "border border-slate-300 rounded px-2 py-1 text-sm w-full"
            }
            attrs[:step] = step if step
            attrs.merge!(disabled_attr)
            input(**attrs)
          end
        end

        def select_field(label_text, attr, options, include_blank: nil)
          field_row(label_text) do
            select(
              name: "paragraph_style[#{attr}]",
              class: "border border-slate-300 rounded px-2 py-1 text-sm w-full",
              **disabled_attr
            ) do
              current = @paragraph_style.public_send(attr)
              option(value: "") { include_blank } if include_blank
              options.each do |opt|
                option(value: opt, selected: opt == current) { opt }
              end
            end
          end
        end

        def font_select(label_text, attr)
          select_field(label_text, attr, Design::Theme::AVAILABLE_FONTS, include_blank: "— inherit —")
        end

        def color_row(label_text, attr)
          field_row(label_text) do
            color_field(attr, @paragraph_style.public_send(attr))
          end
        end

        def color_field(field, value)
          div(class: "flex items-center gap-1 flex-1", data: { controller: "design--color-mode-field" }) do
            input(type: "color", data: { "design--color-mode-field-target": "picker", action: "input->design--color-mode-field#pickerChanged" }, class: "h-7 w-7 cursor-pointer border-0 p-0", **disabled_attr)
            select(data: { "design--color-mode-field-target": "mode", action: "change->design--color-mode-field#modeChanged" }, class: "text-xs px-1 py-0.5", **disabled_attr) do
              option(value: "cmyk") { "CMYK" }
              option(value: "hex") { "Hex" }
              option(value: "named") { "Name" }
            end
            input(type: "text", name: "paragraph_style[#{field}]", value: field_value(value),
                  data: { "design--color-mode-field-target": "input", action: "input->design--color-mode-field#textChanged" },
                  class: "flex-1 border border-slate-300 rounded px-2 py-1",
                  **disabled_attr)
          end
        end

        # Border Side Editor — ports the data-controller="design--border-side-editor" wrapper verbatim
        def border_side_editor
          div do
            label(class: "text-sm text-slate-600") { "Border Sides" }
            div(class: "mt-1", data: { controller: "design--border-side-editor" }) do
              input(type: "hidden", name: "paragraph_style[border_side]", value: field_value(@paragraph_style.border_side), data: { "design--border-side-editor-target": "input" }, **disabled_attr)
              div(class: "flex flex-col items-center gap-0.5") do
                button(type: "button", data: { action: "click->design--border-side-editor#toggle", side: "top" },
                  class: "px-4 py-0.5 text-xs cursor-pointer border border-slate-300 rounded bg-slate-50", **disabled_attr) { "Top" }
                div(class: "flex items-center gap-0.5") do
                  button(type: "button", data: { action: "click->design--border-side-editor#toggle", side: "left" },
                    class: "px-0.5 py-2 text-xs cursor-pointer border border-slate-300 rounded bg-slate-50", **disabled_attr) { "Left" }
                  div(class: "w-20 h-14 bg-slate-50 border border-dashed border-slate-300", data: { "design--border-side-editor-target": "box" })
                  button(type: "button", data: { action: "click->design--border-side-editor#toggle", side: "right" },
                    class: "px-0.5 py-2 text-xs cursor-pointer border border-slate-300 rounded bg-slate-50", **disabled_attr) { "Right" }
                end
                button(type: "button", data: { action: "click->design--border-side-editor#toggle", side: "bottom" },
                  class: "px-3 py-0.5 text-xs cursor-pointer border border-slate-300 rounded bg-slate-50", **disabled_attr) { "Bottom" }
              end
            end
          end
        end

        # Corner Editor — ports the data-controller="design--corner-editor" wrapper verbatim
        def corner_editor
          div do
            label(class: "text-sm text-slate-600") { "Rounded Corners" }
            div(class: "mt-1", data: { controller: "design--corner-editor" }) do
              input(type: "hidden", name: "paragraph_style[rounded_corners]", value: field_value(@paragraph_style.rounded_corners), data: { "design--corner-editor-target": "input" }, **disabled_attr)
              div(class: "flex flex-col items-center gap-0.5") do
                div(class: "flex gap-10") do
                  button(type: "button", data: { action: "click->design--corner-editor#toggle", corner: "tl", "design--corner-editor-target": "tl" },
                    class: "w-7 h-7 text-xs cursor-pointer border border-slate-300 rounded-tl-md flex items-center justify-center", **disabled_attr)
                  button(type: "button", data: { action: "click->design--corner-editor#toggle", corner: "tr", "design--corner-editor-target": "tr" },
                    class: "w-7 h-7 text-xs cursor-pointer border border-slate-300 rounded-tr-md flex items-center justify-center", **disabled_attr)
                end
                div(class: "w-20 h-10 bg-slate-50 border border-slate-300", data: { "design--corner-editor-target": "box" })
                div(class: "flex gap-10") do
                  button(type: "button", data: { action: "click->design--corner-editor#toggle", corner: "bl", "design--corner-editor-target": "bl" },
                    class: "w-7 h-7 text-xs cursor-pointer border border-slate-300 rounded-bl-md flex items-center justify-center", **disabled_attr)
                  button(type: "button", data: { action: "click->design--corner-editor#toggle", corner: "br", "design--corner-editor-target": "br" },
                    class: "w-7 h-7 text-xs cursor-pointer border border-slate-300 rounded-br-md flex items-center justify-center", **disabled_attr)
                end
              end
            end
            div(class: "flex items-center gap-3 mt-2") do
              label(class: "text-sm text-slate-600 w-36 shrink-0") { "Corner Radius" }
              select(name: "paragraph_style[corner_radius]", class: "border border-slate-300 rounded px-2 py-1 text-sm w-full", **disabled_attr) do
                current = @paragraph_style.corner_radius
                option(value: "") { "— none —" }
                %w[none small medium large].each do |opt|
                  option(value: opt, selected: opt == current) { opt }
                end
              end
            end
          end
        end

        def disabled_attr
          @editable ? {} : { disabled: true }
        end

        def field_value(value)
          case value
          when nil then nil
          when BigDecimal then value.to_s("F")
          else value.to_s
          end
        end
      end
    end
  end
end
