module Design
  module Views
    module ParagraphStyles
      # The paragraph-style edit form. Each group is a pastel fieldset box (legend on
      # the top-left of the border); fields render inline (label | control) two per
      # row so the whole form fits beside the preview without scrolling. Font + Text
      # share one box. Behaviour (field names, Stimulus controllers) is unchanged.
      class Fields < Design::Views::Base
        include Design::Views::FieldGroups

        def initialize(paragraph_style:, editable: true)
          @paragraph_style = paragraph_style
          @editable = editable
        end

        def view_template
          identity_section
          type_text_section
          table_cell_section
          bold_emphasis_section
          spacing_section
          fill_section
          border_section
          padding_section
        end

        private

        # ── Sections (each a pastel fieldset box) ──

        def identity_section
          group_box("basic", I18n.t("design.fields.identity")) do
            rows do
              text_field(I18n.t("design.fields.name"), :name)
              text_field(I18n.t("design.fields.korean_name"), :korean_name)
            end
          end
        end

        # Font + Text, merged into one box.
        def type_text_section
          group_box("type_text", "#{I18n.t('design.fields.font')} · #{I18n.t('design.fields.text')}") do
            rows do
              font_select(I18n.t("design.fields.font"), :font)
              number_field(I18n.t("design.fields.size"), :font_size, step: "0.1")
              number_field(I18n.t("design.fields.scale"), :scale, step: "0.01")
              color_row(I18n.t("design.fields.color"), :text_color, span: true)
              select_field(I18n.t("design.fields.align"), :text_align, %w[left center right justify], include_blank: "— inherit —", i18n_scope: "text_align")
              number_field(I18n.t("design.fields.tracking"), :tracking, step: "0.1")
              number_field(I18n.t("design.fields.space_width"), :space_width, step: "0.1")
              number_field(I18n.t("design.fields.line_spacing"), :text_line_spacing, step: "0.1")
            end
          end
        end

        def table_cell_section
          return unless @paragraph_style.name.in?(%w[table_heading_cell table_body_cell])

          group_box("table", I18n.t("design.fields.table_cell")) do
            rows do
              select_field(I18n.t("design.fields.vertical_align"), :vertical_align,
                           Design::ParagraphStyle::VERTICAL_ALIGNS, include_blank: "— inherit —", span: true)
            end
          end
        end

        def bold_emphasis_section
          group_box("bold", I18n.t("design.fields.bold_emphasis")) do
            rows do
              font_select(I18n.t("design.fields.bold_font"), :bold_font)
              font_select(I18n.t("design.fields.emphasis_font"), :emphasis_font)
              color_row(I18n.t("design.fields.bold_color"), :bold_text_color)
              color_row(I18n.t("design.fields.emphasis_color"), :emphasis_color)
            end
          end
        end

        def spacing_section
          group_box("space", I18n.t("design.fields.spacing")) do
            rows do
              number_field(I18n.t("design.fields.first_line_indent"), :first_line_indent, step: "0.1")
              number_field(I18n.t("design.fields.left_indent"), :left_indent, step: "0.1")
              number_field(I18n.t("design.fields.right_indent"), :right_indent, step: "0.1")
              number_field(I18n.t("design.fields.space_before_pt"), :space_before, step: "0.1")
              number_field(I18n.t("design.fields.space_after_pt"), :space_after, step: "0.1")
              number_field(I18n.t("design.fields.space_before_lines"), :space_before_in_lines, step: "0.1")
              number_field(I18n.t("design.fields.space_after_lines"), :space_after_in_lines, step: "0.1")
            end
          end
        end

        def fill_section
          group_box("fill", I18n.t("design.fields.fill")) do
            rows do
              select_field(I18n.t("design.fields.fill_type"), :fill_type, %w[none solid gradient], i18n_scope: "fill_type")
              select_field(I18n.t("design.fields.gradient_dir"), :fill_gradient_direction, %w[top_to_bottom bottom_to_top left_to_right right_to_left angle], include_blank: "— none —", i18n_scope: "gradient_dir")
              color_row(I18n.t("design.fields.fill_color"), :fill_color)
              color_row(I18n.t("design.fields.ending_color"), :fill_ending_color)
            end
          end
        end

        def border_section
          group_box("border", I18n.t("design.fields.border")) do
            rows do
              number_field(I18n.t("design.fields.thickness"), :border_thickness, step: "0.1")
              color_row(I18n.t("design.fields.border_color"), :border_color)
            end
            div(class: "mt-1.5 grid grid-cols-2 gap-2") do
              border_side_editor
              corner_editor
            end
          end
        end

        def padding_section
          group_box("pad", I18n.t("design.fields.padding")) do
            rows do
              number_field(I18n.t("design.fields.padding_top"), :padding_top, step: "0.1")
              number_field(I18n.t("design.fields.padding_bottom"), :padding_bottom, step: "0.1")
            end
          end
        end

        # ── Field helpers (box/row/control helpers come from FieldGroups) ──

        def text_field(label_text, attr, span: false)
          field_row(label_text, span: span) do
            input(type: "text", name: "paragraph_style[#{attr}]", value: field_value(@paragraph_style.public_send(attr)), class: CONTROL, **disabled_attr)
          end
        end

        def number_field(label_text, attr, step: nil, span: false)
          field_row(label_text, span: span, narrow: true) do
            input(type: "text", inputmode: "decimal", name: "paragraph_style[#{attr}]", value: field_value(@paragraph_style.public_send(attr)), class: NUMBER_CONTROL, **disabled_attr)
          end
        end

        def select_field(label_text, attr, options, include_blank: nil, i18n_scope: nil, span: false)
          field_row(label_text, span: span) do
            select(name: "paragraph_style[#{attr}]", class: CONTROL, **disabled_attr) do
              current = @paragraph_style.public_send(attr)
              option(value: "") { include_blank } if include_blank
              options.each do |opt|
                label = i18n_scope ? I18n.t("design.options.#{i18n_scope}.#{opt}") : opt
                option(value: opt, selected: opt == current) { label }
              end
            end
          end
        end

        # Font names are long → full row.
        def font_select(label_text, attr)
          select_field(label_text, attr, Design::Theme::AVAILABLE_FONTS, include_blank: "— inherit —", span: true)
        end

        def color_row(label_text, attr, span: false)
          field_row(label_text, span: span) do
            color_field(attr, @paragraph_style.public_send(attr))
          end
        end

        def color_field(field, value)
          div(class: "flex min-w-0 flex-1 items-center gap-1.5", data: { controller: "design--color-mode-field" }) do
            input(type: "color", data: { "design--color-mode-field-target": "picker", action: "input->design--color-mode-field#pickerChanged" }, class: "h-8 w-8 shrink-0 cursor-pointer rounded border border-slate-300 p-0", **disabled_attr)
            select(data: { "design--color-mode-field-target": "mode", action: "change->design--color-mode-field#modeChanged" }, class: "shrink-0 rounded border border-slate-300 px-1 py-0.5 text-xs", **disabled_attr) do
              option(value: "cmyk") { "CMYK" }
              option(value: "hex") { "Hex" }
              option(value: "named") { "Name" }
            end
            input(type: "text", name: "paragraph_style[#{field}]", value: field_value(value),
                  data: { "design--color-mode-field-target": "input", action: "input->design--color-mode-field#textChanged" },
                  class: "h-8 min-w-0 flex-1 rounded border border-slate-300 px-2 text-sm",
                  **disabled_attr)
          end
        end

        # ── Border side / corner editors (compact; behaviour unchanged) ──

        def border_side_editor
          div do
            label(class: "text-xs text-slate-600") { I18n.t("design.fields.border_sides") }
            div(class: "mt-0.5", data: { controller: "design--border-side-editor" }) do
              input(type: "hidden", name: "paragraph_style[border_side]", value: field_value(@paragraph_style.border_side), data: { "design--border-side-editor-target": "input" }, **disabled_attr)
              div(class: "flex flex-col items-center gap-0.5") do
                button(type: "button", data: { action: "click->design--border-side-editor#toggle", side: "top" },
                  class: "px-3 py-0.5 text-xs cursor-pointer border border-slate-300 rounded bg-white", **disabled_attr) { I18n.t("design.shared.top") }
                div(class: "flex items-center gap-0.5") do
                  button(type: "button", data: { action: "click->design--border-side-editor#toggle", side: "left" },
                    class: "px-0.5 py-1.5 text-xs cursor-pointer border border-slate-300 rounded bg-white", **disabled_attr) { I18n.t("design.shared.left") }
                  div(class: "w-14 h-10 bg-white border border-dashed border-slate-300", data: { "design--border-side-editor-target": "box" })
                  button(type: "button", data: { action: "click->design--border-side-editor#toggle", side: "right" },
                    class: "px-0.5 py-1.5 text-xs cursor-pointer border border-slate-300 rounded bg-white", **disabled_attr) { I18n.t("design.shared.right") }
                end
                button(type: "button", data: { action: "click->design--border-side-editor#toggle", side: "bottom" },
                  class: "px-2 py-0.5 text-xs cursor-pointer border border-slate-300 rounded bg-white", **disabled_attr) { I18n.t("design.shared.bottom") }
              end
            end
          end
        end

        def corner_editor
          div do
            label(class: "text-xs text-slate-600") { I18n.t("design.fields.rounded_corners") }
            div(class: "mt-0.5", data: { controller: "design--corner-editor" }) do
              input(type: "hidden", name: "paragraph_style[rounded_corners]", value: field_value(@paragraph_style.rounded_corners), data: { "design--corner-editor-target": "input" }, **disabled_attr)
              div(class: "flex flex-col items-center gap-0.5") do
                div(class: "flex gap-8") do
                  button(type: "button", data: { action: "click->design--corner-editor#toggle", corner: "tl", "design--corner-editor-target": "tl" },
                    class: "w-6 h-6 text-xs cursor-pointer border border-slate-300 rounded-tl-md flex items-center justify-center bg-white", **disabled_attr)
                  button(type: "button", data: { action: "click->design--corner-editor#toggle", corner: "tr", "design--corner-editor-target": "tr" },
                    class: "w-6 h-6 text-xs cursor-pointer border border-slate-300 rounded-tr-md flex items-center justify-center bg-white", **disabled_attr)
                end
                div(class: "w-14 h-8 bg-white border border-slate-300", data: { "design--corner-editor-target": "box" })
                div(class: "flex gap-8") do
                  button(type: "button", data: { action: "click->design--corner-editor#toggle", corner: "bl", "design--corner-editor-target": "bl" },
                    class: "w-6 h-6 text-xs cursor-pointer border border-slate-300 rounded-bl-md flex items-center justify-center bg-white", **disabled_attr)
                  button(type: "button", data: { action: "click->design--corner-editor#toggle", corner: "br", "design--corner-editor-target": "br" },
                    class: "w-6 h-6 text-xs cursor-pointer border border-slate-300 rounded-br-md flex items-center justify-center bg-white", **disabled_attr)
                end
              end
            end
            div(class: "mt-1 flex items-center gap-1.5") do
              label(class: "shrink-0 text-sm text-slate-600") { I18n.t("design.fields.corner_radius") }
              select(name: "paragraph_style[corner_radius]", class: "h-8 min-w-0 flex-1 rounded border border-slate-300 px-2 text-sm", **disabled_attr) do
                current = @paragraph_style.corner_radius
                option(value: "") { "— none —" }
                %w[none small medium large].each do |opt|
                  option(value: opt, selected: opt == current) { I18n.t("design.options.corner_radius.#{opt}") }
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
