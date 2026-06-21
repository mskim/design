module Design
  module Views
    module PaperSizes
      class Edit < Design::Views::Base
        def initialize(theme:, paper_size:, base_styles:)
          @theme = theme
          @paper_size = paper_size
          @base_styles = base_styles
        end

        def view_template
          div(class: "design-studio mx-auto max-w-4xl px-6 py-10 flex flex-col gap-8") do
            render Design::Views::Breadcrumb.new(crumbs: [
              [ @theme.name, helpers.theme_path(@theme) ],
              [ @paper_size.display_name, nil ]
            ])

            h1(class: "text-2xl font-semibold text-slate-900") { @paper_size.display_name }

            edit_form
            base_styles_section if @base_styles.any?
          end
        end

        private

        def edit_form
          form(
            action: helpers.theme_paper_size_path(@theme, @paper_size),
            method: "post",
            class: "flex flex-col gap-4"
          ) do
            input(type: "hidden", name: "_method", value: "patch")
            input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)

            h2(class: "text-lg font-medium text-slate-900") { "Margins (mm)" }
            div(class: "grid grid-cols-1 gap-3 sm:grid-cols-2") do
              margin_field("Left", :left_margin_mm)
              margin_field("Top", :top_margin_mm)
              margin_field("Right", :right_margin_mm)
              margin_field("Bottom", :bottom_margin_mm)
            end

            margin_field("Binding Margin (mm)", :binding_margin_mm)
            integer_field("Body Line Count", :body_line_count)
            integer_field("TOC Page Count", :toc_page_count)

            div(class: "flex items-center gap-3") do
              button(
                type: "submit",
                class: "inline-flex items-center rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-700"
              ) { "Save" }
              a(
                href: helpers.theme_path(@theme),
                class: "text-sm font-medium text-blue-600 hover:underline"
              ) { "Cancel" }
            end
          end
        end

        def margin_field(label_text, attr)
          number_field(label_text, attr, step: "0.1")
        end

        def integer_field(label_text, attr)
          number_field(label_text, attr, step: nil)
        end

        def number_field(label_text, attr, step:)
          div(class: "flex items-center gap-3") do
            label(class: "text-sm text-slate-600 w-40") { label_text }
            attrs = {
              type: "number",
              name: "paper_size[#{attr}]",
              value: field_value(@paper_size.public_send(attr)),
              class: "border border-slate-300 rounded px-2 py-1 text-sm"
            }
            attrs[:step] = step if step
            input(**attrs)
          end
        end

        def field_value(value)
          case value
          when nil then nil
          when BigDecimal then value.to_s("F")
          else value.to_s
          end
        end

        def base_styles_section
          section(class: "flex flex-col gap-3") do
            h2(class: "text-lg font-medium text-slate-900") { "Base Text Styles" }
            div(class: "flex flex-col gap-2") do
              @base_styles.each { |style| base_style_row(style) }
            end
          end
        end

        def base_style_row(style)
          RubyUI::Card(class: "p-3 flex items-center justify-between gap-3") do
            div(class: "flex items-center gap-2 flex-wrap") do
              span(class: "font-medium text-slate-900") { style.name }
              if style.korean_name.present?
                span(class: "text-sm text-slate-500") { "(#{style.korean_name})" }
              end
              span(class: "text-sm text-slate-500") do
                plain "— #{style.font || "inherit"}, #{style.font_size || "inherit"}pt"
              end
            end
            a(
              href: helpers.edit_theme_paper_size_base_paragraph_style_path(@theme, @paper_size, style),
              class: "text-sm font-medium text-blue-600 hover:underline"
            ) { "Edit →" }
          end
        end
      end
    end
  end
end
