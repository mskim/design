module Design
  module Views
    module Themes
      class Form < Design::Views::Base
        def initialize(theme:)
          @theme = theme
        end

        def view_template
          shell(title: @theme.persisted? ? I18n.t("design.themes.edit_title") : I18n.t("design.themes.new_title")) do
            div(class: "max-w-2xl mx-auto p-8") do
              render_errors
              render_form
            end
          end
        end

        private

        def render_form
          url = @theme.persisted? ? helpers.theme_path(@theme) : helpers.themes_path
          method = @theme.persisted? ? :patch : :post
          form(action: url, method: :post, class: "space-y-6") do
            input(type: :hidden, name: "authenticity_token", value: helpers.form_authenticity_token)
            input(type: :hidden, name: "_method", value: method.to_s) if method == :patch

            section(I18n.t("design.themes.identity")) do
              field(I18n.t("design.themes.name_label"), :name, required: true)
              field(I18n.t("design.themes.description_label"), :description, type: :textarea)
              select_field(I18n.t("design.themes.locale_label"), :locale, %w[ko en ja zh])
            end
            section(I18n.t("design.themes.default_fonts")) do
              font_select_field(I18n.t("design.themes.body_font"), :base_body_font)
              field(I18n.t("design.themes.body_font_size"), :base_body_font_size, type: :number, step: "0.1")
              font_select_field(I18n.t("design.themes.heading_font"), :base_heading_font)
            end
            div(class: "flex gap-3") do
              render RubyUI::Button.new(variant: :primary, type: :submit) do
                @theme.persisted? ? I18n.t("design.themes.update_button") : I18n.t("design.themes.create_button")
              end
              a(href: helpers.themes_path) { render RubyUI::Button.new(variant: :outline) { I18n.t("design.shared.cancel") } }
            end
          end
        end

        def section(title, &block)
          div(class: "space-y-4") do
            h3(class: "text-lg font-medium border-b pb-2") { title }
            yield
          end
        end

        def field(label_text, attr, type: :text, **opts)
          div do
            label(class: "block text-sm font-medium mb-1") { label_text }
            if type == :textarea
              textarea(name: "theme[#{attr}]", rows: 3,
                       class: "w-full rounded-md border border-input bg-background px-3 py-2 text-sm") { @theme.send(attr) }
            else
              input(type: type, name: "theme[#{attr}]", value: @theme.send(attr).to_s,
                    class: "w-full rounded-md border border-input bg-background px-3 py-2 text-sm", **opts)
            end
          end
        end

        def font_select_field(label_text, attr)
          current = @theme.send(attr).to_s
          div do
            label(class: "block text-sm font-medium mb-1") { label_text }
            select(name: "theme[#{attr}]", class: "w-full rounded-md border border-input bg-background px-3 py-2 text-sm") do
              option(value: "", selected: current.empty?) { "— default —" }
              Design::Theme::AVAILABLE_FONTS.each { |f| option(value: f, selected: current == f) { f } }
            end
          end
        end

        def select_field(label_text, attr, options)
          div do
            label(class: "block text-sm font-medium mb-1") { label_text }
            select(name: "theme[#{attr}]", class: "w-full rounded-md border border-input bg-background px-3 py-2 text-sm") do
              options.each { |opt| option(value: opt, selected: @theme.send(attr) == opt) { opt } }
            end
          end
        end

        # The gem has NO RubyUI::Alert — plain div.
        def render_errors
          return unless @theme.errors.any?
          div(class: "mb-4 rounded-md border border-red-300 bg-red-50 p-3 text-sm text-red-700") do
            ul(class: "list-disc pl-4") { @theme.errors.full_messages.each { |m| li { m } } }
          end
        end
      end
    end
  end
end
