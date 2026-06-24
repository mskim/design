module Design
  module Views
    module PaperSizes
      class Form < Design::Views::Base
        def initialize(theme:, paper_size:, base_styles: [])
          @theme = theme
          @paper_size = paper_size
          @base_styles = base_styles
        end

        def view_template
          title = @paper_size.persisted? ? @paper_size.display_name : I18n.t("design.paper_sizes.new_title")
          shell(title: title, action_slot: nil, sidebar: nil) do
            div(class: "mx-auto max-w-4xl px-6 py-10 flex flex-col gap-8") do
              render Design::Views::Breadcrumb.new(crumbs: [
                [ @theme.name, helpers.theme_path(@theme) ],
                [ title, nil ]
              ])
              h1(class: "text-2xl font-semibold text-slate-900") { title }
              render_errors
              edit_form
              base_styles_section if @paper_size.persisted? && @base_styles.any?
            end
          end
        end

        private

        def edit_form
          url    = @paper_size.persisted? ? helpers.theme_paper_size_path(@theme, @paper_size) : helpers.theme_paper_sizes_path(@theme)
          method = @paper_size.persisted? ? "patch" : "post"
          form(action: url, method: "post", class: "flex flex-col gap-6") do
            input(type: "hidden", name: "_method", value: method) if method == "patch"
            input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)

            h2(class: "text-lg font-medium text-slate-900") { I18n.t("design.paper_sizes.page_size") }
            div(class: "grid grid-cols-1 gap-3 sm:grid-cols-2") do
              text_field(I18n.t("design.paper_sizes.size_name"), :size_name, required: true)
              text_field(I18n.t("design.paper_sizes.local_name"), :local_name)
              number_field(I18n.t("design.paper_sizes.width"), :width_mm, step: "0.1")
              number_field(I18n.t("design.paper_sizes.height"), :height_mm, step: "0.1")
            end

            h2(class: "text-lg font-medium text-slate-900") { I18n.t("design.paper_sizes.margins") }
            div(class: "grid grid-cols-1 gap-3 sm:grid-cols-2") do
              number_field(I18n.t("design.shared.left"), :left_margin_mm, step: "0.1")
              number_field(I18n.t("design.shared.top"), :top_margin_mm, step: "0.1")
              number_field(I18n.t("design.shared.right"), :right_margin_mm, step: "0.1")
              number_field(I18n.t("design.shared.bottom"), :bottom_margin_mm, step: "0.1")
            end
            number_field(I18n.t("design.paper_sizes.binding_margin"), :binding_margin_mm, step: "0.1")

            h2(class: "text-lg font-medium text-slate-900") { I18n.t("design.paper_sizes.body_settings") }
            number_field(I18n.t("design.paper_sizes.body_line_count"), :body_line_count, step: nil)
            number_field(I18n.t("design.paper_sizes.toc_page_count"), :toc_page_count, step: nil)

            primary_label = @paper_size.persisted? ? I18n.t("design.paper_sizes.update_button") : I18n.t("design.paper_sizes.create_button")
            div(class: "flex items-center gap-3") do
              render RubyUI::Button.new(variant: :primary, type: :submit) { primary_label }
              a(href: helpers.theme_path(@theme)) { render RubyUI::Button.new(variant: :outline) { I18n.t("design.shared.cancel") } }
            end
          end

          secondary_actions if @paper_size.persisted?
        end

        # Regenerate + Delete are separate forms (own method/confirm) so they don't nest in the main form.
        def secondary_actions
          div(class: "flex items-center gap-3 border-t border-slate-200 pt-4") do
            form(action: helpers.regenerate_theme_paper_size_path(@theme, @paper_size), method: "post", class: "inline") do
              input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
              render RubyUI::Button.new(variant: :outline, type: :submit) { I18n.t("design.paper_sizes.regenerate") }
            end
            form(action: helpers.theme_paper_size_path(@theme, @paper_size), method: "post", class: "inline",
                 data: { turbo_confirm: I18n.t("design.paper_sizes.delete_confirm") }) do
              input(type: "hidden", name: "_method", value: "delete")
              input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
              render RubyUI::Button.new(variant: :destructive, type: :submit) { I18n.t("design.paper_sizes.delete") }
            end
          end
        end

        def text_field(label_text, attr, required: false)
          div(class: "flex items-center gap-3") do
            label(class: "text-sm text-slate-600 w-40") { label_text }
            input(type: "text", name: "paper_size[#{attr}]", value: @paper_size.public_send(attr).to_s,
                  required: required, class: "border border-slate-300 rounded px-2 py-1 text-sm")
          end
        end

        def number_field(label_text, attr, step:)
          div(class: "flex items-center gap-3") do
            label(class: "text-sm text-slate-600 w-40") { label_text }
            attrs = { type: "number", name: "paper_size[#{attr}]",
                      value: field_value(@paper_size.public_send(attr)),
                      class: "border border-slate-300 rounded px-2 py-1 text-sm" }
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

        # The gem has NO RubyUI::Alert — plain div (mirrors themes/form.rb).
        def render_errors
          return unless @paper_size.errors.any?
          div(class: "mb-4 rounded-md border border-red-300 bg-red-50 p-3 text-sm text-red-700") do
            ul(class: "list-disc pl-4") { @paper_size.errors.full_messages.each { |m| li { m } } }
          end
        end

        def base_styles_section
          section(class: "flex flex-col gap-3") do
            h2(class: "text-lg font-medium text-slate-900") { I18n.t("design.paper_sizes.base_text_styles") }
            div(class: "flex flex-col gap-2") { @base_styles.each { |style| base_style_row(style) } }
          end
        end

        def base_style_row(style)
          RubyUI::Card(class: "p-3 flex items-center justify-between gap-3") do
            div(class: "flex items-center gap-2 flex-wrap") do
              span(class: "font-medium text-slate-900") { style.name }
              span(class: "text-sm text-slate-500") { "(#{style.korean_name})" } if style.korean_name.present?
              span(class: "text-sm text-slate-500") { plain "— #{style.font || "inherit"}, #{style.font_size || "inherit"}pt" }
            end
            a(href: helpers.edit_theme_paper_size_base_paragraph_style_path(@theme, @paper_size, style),
              class: "text-sm font-medium text-blue-600 hover:underline") { I18n.t("design.shared.edit") }
          end
        end
      end
    end
  end
end
