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

        def styles_table
          div(class: "overflow-x-auto") do
            table(class: "w-full text-sm") do
              thead do
                tr(class: "border-b border-slate-200 text-slate-700") do
                  %w[name korean theme size doc_type font font_size color fill border actions].each do |k|
                    align = %w[font_size].include?(k) ? "text-right" : (k == "actions" ? "text-center" : "text-left")
                    th(class: "#{align} py-2 px-2 font-medium") { I18n.t("design.style_browser.col_#{k}") }
                  end
                end
              end
              tbody do
                @style_rows.each { |row| style_row(row) }
              end
            end
          end
        end

        def style_row(row)
          style = row[:style]
          tr(class: "border-b border-slate-100 hover:bg-slate-50") do
            td(class: "py-2 px-2 font-medium text-slate-900") { style.name }
            td(class: "py-2 px-2 text-slate-500") { style.korean_name.presence || "—" }
            td(class: "py-2 px-2") { row[:theme].name }
            td(class: "py-2 px-2") { row[:paper_size].size_name }
            td(class: "py-2 px-2") { doc_type_cell(row) }
            td(class: "py-2 px-2") { style.font.presence || "—" }
            td(class: "py-2 px-2 text-right") { style.font_size&.to_s || "—" }
            td(class: "py-2 px-2") { color_swatch(style.text_color) }
            td(class: "py-2 px-2") { fill_info(style) }
            td(class: "py-2 px-2") { border_info(style) }
            td(class: "py-2 px-2 text-center") { actions_cell(row) }   # filled in Task 3
          end
        end

        def doc_type_cell(row)
          if row[:doc_type].nil?
            span(class: "text-slate-400 italic") { I18n.t("design.style_browser.all_docs") }
          elsif row[:is_override]
            div(class: "flex items-center gap-1") do
              plain doc_type_label(row[:doc_type])
              RubyUI::Badge(variant: :slate, size: :sm) { I18n.t("design.style_browser.override") }
            end
          else
            plain doc_type_label(row[:doc_type])
          end
        end

        def color_swatch(color)
          return plain("—") unless color.present?
          div(class: "flex items-center gap-1") do
            span(class: "inline-block w-3 h-3 rounded-full border border-slate-300", style: "background-color: #{color}")
            span(class: "text-xs") { color }
          end
        end

        def fill_info(style)
          return plain("—") unless style.fill_type.present? && style.fill_color.present?
          div(class: "flex items-center gap-1") do
            span(class: "inline-block w-3 h-3 rounded border border-slate-300", style: "background-color: #{style.fill_color}")
            span(class: "text-xs") { style.fill_type }
          end
        end

        def border_info(style)
          return plain("—") unless style.border_thickness.present? && style.border_thickness > 0
          div(class: "flex items-center gap-1") do
            span(class: "inline-block w-3 h-3 rounded border border-slate-300", style: "background-color: #{style.border_color}") if style.border_color.present?
            span(class: "text-xs") { "#{style.border_thickness}pt" }
          end
        end

        # Filled in Task 3.
        def actions_cell(row)
          plain ""
        end
      end
    end
  end
end
