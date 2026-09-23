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
              number_field(I18n.t("design.fields.size"), :font_size, step: "0.1", min: 0)
              number_field(I18n.t("design.fields.scale"), :scale, step: "1", min: 0, unit: :percent)
              color_row(I18n.t("design.fields.color"), :text_color, span: true)
              select_field(I18n.t("design.fields.align"), :text_align, %w[left center right justify], include_blank: "— inherit —", i18n_scope: "text_align")
              number_field(I18n.t("design.fields.tracking"), :tracking, step: "0.1", unit: :none)
              number_field(I18n.t("design.fields.space_width"), :space_width, step: "0.1", unit: :none)
              number_field(I18n.t("design.fields.line_spacing"), :text_line_spacing, step: "0.1", min: 0)
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
              number_field(I18n.t("design.fields.space_before_pt"), :space_before, step: "0.1", min: 0)
              number_field(I18n.t("design.fields.space_after_pt"), :space_after, step: "0.1", min: 0)
              number_field(I18n.t("design.fields.space_before_lines"), :space_before_in_lines, step: "0.1", min: 0, unit: :lines)
              number_field(I18n.t("design.fields.space_after_lines"), :space_after_in_lines, step: "0.1", min: 0, unit: :lines)
            end
          end
        end

        def fill_section
          group_box("fill", I18n.t("design.fields.fill")) do
            rows do
              select_field(I18n.t("design.fields.fill_type"), :fill_type, %w[none solid gradient], include_blank: "— inherit —", i18n_scope: "fill_type")
              select_field(I18n.t("design.fields.gradient_dir"), :fill_gradient_direction, %w[top_to_bottom bottom_to_top left_to_right right_to_left angle], include_blank: "— none —", i18n_scope: "gradient_dir")
              color_row(I18n.t("design.fields.fill_color"), :fill_color)
              color_row(I18n.t("design.fields.ending_color"), :fill_ending_color)
            end
          end
        end

        # D5: a thickness and a colour per side, a preset per corner (no 🔗 here:
        # this form submits as a whole).
        def border_section
          group_box("border", I18n.t("design.fields.border")) do
            rows do
              Design::ParagraphStyle::SIDES.each do |s|
                number_field(I18n.t("design.fields.border_#{s}_thickness"), :"border_#{s}_thickness", step: "0.1", min: 0)
                color_row(I18n.t("design.fields.border_#{s}_color"), :"border_#{s}_color")
              end
              %w[top_left top_right bottom_left bottom_right].each do |c|
                select_field(I18n.t("design.fields.corner_#{c}"), :"corner_#{c}", Design::ParagraphStyle::CORNER_SIZES,
                             include_blank: "—", i18n_scope: "corner_size")
              end
            end
          end
        end

        def padding_section
          group_box("pad", I18n.t("design.fields.padding")) do
            rows do
              number_field(I18n.t("design.fields.padding_top"), :padding_top, step: "0.1", min: 0)
              number_field(I18n.t("design.fields.padding_bottom"), :padding_bottom, step: "0.1", min: 0)
            end
          end
        end

        # ── Field helpers (box/row/control helpers come from FieldGroups) ──

        def text_field(label_text, attr, span: false)
          field_row(label_text, span: span) do
            input(type: "text", name: "paragraph_style[#{attr}]", value: field_value(@paragraph_style.public_send(attr)),
                  class: CONTROL, **disabled_attr)
          end
        end

        # min: 0 for sizes/spacing that can't be negative; indents and tracking stay unbounded.
        def number_field(label_text, attr, step: nil, span: false, unit: :pt, min: nil)
          render Design::Views::Inputs::NumberField.new(
            name: "paragraph_style[#{attr}]", value: field_value(@paragraph_style.public_send(attr)),
            label: label_text, unit: unit, step: (step || 0.1).to_f, min: min, span: span,
            disabled: disabled_attr[:disabled] == true)
        end

        # A nil value selects the blank option (so an inherited field posts "" and
        # stays inherited); a current value missing from `options` is added as an
        # extra option so it round-trips unchanged.
        def select_field(label_text, attr, options, include_blank: nil, i18n_scope: nil, span: false)
          field_row(label_text, span: span) do
            select(name: "paragraph_style[#{attr}]", class: CONTROL, **disabled_attr) do
              current = @paragraph_style.public_send(attr)
              option(value: "") { include_blank } if include_blank
              select_options(options, current).each do |opt|
                label = i18n_scope && options.include?(opt) ? I18n.t("design.options.#{i18n_scope}.#{opt}") : opt
                option(value: opt, selected: opt == current) { label }
              end
            end
          end
        end

        def select_options(options, current)
          current.present? && !options.include?(current) ? options + [ current ] : options
        end

        # Font names are long → full row.
        def font_select(label_text, attr)
          select_field(label_text, attr, Design::Theme::AVAILABLE_FONTS, include_blank: "— inherit —", span: true)
        end

        def color_row(label_text, attr, span: false)
          render Design::Views::Inputs::ColorField.new(
            name: "paragraph_style[#{attr}]", value: @paragraph_style.public_send(attr),
            label: label_text, span: span, disabled: disabled_attr[:disabled] == true)
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
