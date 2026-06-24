module Design
  module Views
    module ParagraphStyles
      class Browser < Design::Views::Base
        def initialize(themes:, size_names:, doc_types:, style_names:, style_rows:,
                       selected_theme:, selected_size:, selected_doc_type:, selected_style_name:)
          @themes = themes
          @size_names = size_names
          @doc_types = doc_types
          @style_names = style_names
          @style_rows = style_rows
          @selected_theme = selected_theme
          @selected_size = selected_size
          @selected_doc_type = selected_doc_type
          @selected_style_name = selected_style_name
        end

        def view_template
          shell(title: I18n.t("design.style_browser.title"), action_slot: nil, sidebar: nil) do
            div(class: "mx-auto max-w-7xl px-6 py-10 flex flex-col gap-6") do
              header_section
              filters_section
              results_section
            end
          end
        end

        private

        def header_section
          div(class: "flex items-center justify-between") do
            div do
              h1(class: "text-2xl font-semibold text-slate-900") { I18n.t("design.style_browser.title") }
              p(class: "text-sm text-slate-500 mt-1") { I18n.t("design.style_browser.count", count: @style_rows.count) }
            end
            a(href: helpers.themes_path) { render RubyUI::Button.new(variant: :outline) { I18n.t("design.style_browser.back_to_themes") } }
          end
        end

        def filters_section
          RubyUI::Card(class: "p-6") do
            form(action: helpers.style_browser_path, method: :get, data: { controller: "design--auto-submit" }) do
              div(class: "flex flex-wrap gap-4 items-end") do
                filter_select(I18n.t("design.style_browser.f_theme"), "theme", @themes.map(&:name), @selected_theme)
                filter_select(I18n.t("design.style_browser.f_size"), "size", @size_names, @selected_size)
                filter_select(I18n.t("design.style_browser.f_doc_type"), "doc_type", @doc_types, @selected_doc_type)
                filter_select(I18n.t("design.style_browser.f_style"), "style_name", @style_names, @selected_style_name)
              end
            end
          end
        end

        def filter_select(label_text, param_name, options, selected_value)
          div(class: "flex-1 min-w-[160px]") do
            label(class: "block text-sm font-medium text-slate-700 mb-1") { label_text }
            select(name: param_name, class: "w-full border border-slate-300 rounded-md px-3 py-2 text-sm bg-white",
                   data: { action: "change->design--auto-submit#submit" }) do
              option(value: "") { I18n.t("design.style_browser.all") }
              options.each do |opt|
                opt == selected_value ? option(value: opt, selected: true) { opt } : option(value: opt) { opt }
              end
            end
          end
        end

        def results_section
          RubyUI::Card(class: "p-6") do
            if @style_rows.any?
              styles_table
            else
              p(class: "text-sm text-slate-500") { I18n.t("design.style_browser.empty") }
            end
          end
        end

        # Filled in Task 2.
        def styles_table
          div { "" }
        end
      end
    end
  end
end
