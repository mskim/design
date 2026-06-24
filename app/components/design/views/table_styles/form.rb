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
                  field(I18n.t("design.table_styles.width"), :border_width, type: "number", step: "0.1")
                  select_field(I18n.t("design.table_styles.style"), :border_style, Design::TableStyle::BORDER_STYLES)
                end
                color_field(I18n.t("design.table_styles.color"), :border_color)
                row do
                  field(I18n.t("design.table_styles.outer_width"), :outer_border_width, type: "number", step: "0.1")
                  field(I18n.t("design.table_styles.header_sep"), :header_separator_width, type: "number", step: "0.1")
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
                  field(I18n.t("design.table_styles.cell_padding"), :cell_padding, type: "number", step: "0.5")
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

        def field(label_text, attr, type: "text", **opts)
          div do
            label(class: "block text-xs text-slate-500 mb-0.5") { label_text }
            input(type: type, name: "table_style[#{attr}]", value: @style.public_send(attr).to_s,
                  class: "w-full rounded-md border border-slate-300 px-2.5 py-1 text-sm", **opts)
          end
        end

        def color_field(label_text, attr)
          div(data: { controller: "design--color-field" }) do
            label(class: "block text-xs text-slate-500 mb-0.5") { label_text }
            div(class: "flex gap-1.5 items-center") do
              input(type: "color", value: normalize_color(@style.public_send(attr)),
                    class: "w-7 h-7 rounded border border-slate-300 cursor-pointer shrink-0 p-0",
                    data: { "design--color-field-target": "picker", action: "input->design--color-field#pickerChanged" })
              input(type: "text", name: "table_style[#{attr}]", value: @style.public_send(attr).to_s, placeholder: "#rrggbb",
                    class: "flex-1 min-w-0 rounded-md border border-slate-300 px-2 py-1 text-sm",
                    data: { "design--color-field-target": "text", action: "input->design--color-field#textChanged" })
            end
          end
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

        def normalize_color(color)
          return "#ffffff" if color.nil? || color.to_s.strip.empty?
          color.to_s.start_with?("#") ? color : "#ffffff"
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
