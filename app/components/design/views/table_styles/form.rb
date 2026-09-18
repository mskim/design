module Design
  module Views
    module TableStyles
      class Form < Design::Views::Base
        def initialize(theme:, table_style:)
          @theme = theme
          @style = table_style
        end

        def view_template
          form(action: helpers.theme_table_style_path(@theme, @style), method: "post", class: "flex-1 flex flex-col") do
            input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
            input(type: "hidden", name: "_method", value: "patch")
            render_errors
            div(class: "flex-1 px-4 py-3 flex flex-col gap-4") do
              section(I18n.t("design.table_styles.borders")) do
                row do
                  number_field(I18n.t("design.table_styles.width"), :border_width, step: "0.1")
                  select_field(I18n.t("design.table_styles.style"), :border_style, Design::TableStyle::BORDER_STYLES)
                end
                color_field(I18n.t("design.table_styles.color"), :border_color)
                row do
                  number_field(I18n.t("design.table_styles.outer_width"), :outer_border_width, step: "0.1")
                  number_field(I18n.t("design.table_styles.header_sep"), :header_separator_width, step: "0.1")
                end
              end
              section(I18n.t("design.table_styles.backgrounds")) do
                color_field(I18n.t("design.table_styles.header_bg"), :header_background)
                color_field(I18n.t("design.table_styles.alt_row_bg"), :alternate_row_background)
              end
              section(I18n.t("design.table_styles.cell_text")) do
                row do
                  color_field(I18n.t("design.table_styles.header_color"), :header_text_color)
                  color_field(I18n.t("design.table_styles.body_color"), :body_text_color)
                end
                row do
                  select_field(I18n.t("design.table_styles.header_weight"), :header_font_weight, Design::TableStyle::FONT_WEIGHTS)
                  number_field(I18n.t("design.table_styles.cell_padding"), :cell_padding, step: "0.5")
                end
              end
            end
            div(class: "border-t border-slate-200 px-4 py-3 flex items-center justify-end gap-2") do
              render RubyUI::Button.new(variant: :primary, type: :submit) { I18n.t("design.shared.save") }
              a(href: helpers.theme_path(@theme)) { render RubyUI::Button.new(variant: :outline) { I18n.t("design.table_styles.done") } }
            end
          end
        end

        private

        def section(title, &block)
          div(class: "flex flex-col gap-2") do
            h3(class: "text-xs font-semibold uppercase tracking-wider text-slate-500") { title }
            div(class: "flex flex-col gap-2", &block)
          end
        end

        def row(&block) = div(class: "grid grid-cols-2 gap-3", &block)

        def number_field(label_text, attr, step:)
          render Design::Views::Inputs::NumberField.new(
            name: "table_style[#{attr}]", value: @style.public_send(attr).to_s,
            label: label_text, unit: :pt, step: step.to_f, min: 0, layout: :stacked)
        end

        # Table colours are read by TableStyleResolver through HexToCmyk (hex only).
        def color_field(label_text, attr)
          render Design::Views::Inputs::ColorField.new(
            name: "table_style[#{attr}]", value: @style.public_send(attr), label: label_text,
            layout: :stacked, formats: [ :hex ])
        end

        def select_field(label_text, attr, options)
          current = @style.public_send(attr).to_s
          div do
            label(class: "block text-xs text-slate-500 mb-0.5") { label_text }
            select(name: "table_style[#{attr}]", class: "w-full rounded-md border border-slate-300 px-2.5 py-1 text-sm") do
              options.each { |opt| option(value: opt, selected: current == opt) { opt } }
            end
          end
        end

        def render_errors
          return unless @style.errors.any?
          div(class: "rounded-md border border-red-300 bg-red-50 p-3 mb-2 mx-4 mt-2") do
            ul(class: "list-disc pl-4 text-sm text-red-700") { @style.errors.full_messages.each { |m| li { m } } }
          end
        end
      end
    end
  end
end
