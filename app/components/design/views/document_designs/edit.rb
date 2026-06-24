module Design
  module Views
    module DocumentDesigns
      class Edit < Design::Views::Base
        register_element :turbo_frame

        def initialize(theme:, paper_size:, document_design:, paragraph_styles:, editable: true)
          @theme = theme
          @paper_size = paper_size
          @document_design = document_design
          @paragraph_styles = paragraph_styles
          @editable = editable
        end

        def view_template
          shell(title: doc_type_label(@document_design.doc_type), action_slot: nil, sidebar: nil) do
            div(class: "mx-auto max-w-6xl px-6 py-10 flex flex-col gap-8") do
              render Design::Views::DocumentDesigns::EditorToolbar.new(
                theme: @theme, paper_size: @paper_size, document_design: @document_design
              )

              h1(class: "text-2xl font-semibold text-slate-900") { doc_type_label(@document_design.doc_type) }

              div(class: "flex flex-col lg:flex-row gap-6") do
                div(class: "flex-1 min-w-0") { preview_section }
                div(class: "lg:w-[28rem] lg:shrink-0") { render Design::Views::DocumentDesigns::PropertiesPanel.new(theme: @theme, paper_size: @paper_size, document_design: @document_design, editable: @editable) }
              end
              document_styles_section if @paragraph_styles.any?
              base_styles_section
            end
          end
        end

        private

        def preview_section
          div(class: "rounded-lg border border-slate-200 bg-slate-50 p-4") do
            h2(class: "mb-2 text-sm font-medium text-slate-700") { I18n.t("design.editor.preview") }
            turbo_frame(id: "preview_frame",
                        src: helpers.preview_theme_paper_size_document_design_path(@theme, @paper_size, @document_design),
                        loading: "lazy") do
              div(class: "p-8 text-center text-slate-400") { I18n.t("design.editor.loading_preview") }
            end
          end
        end

        def document_styles_section
          section(class: "flex flex-col gap-3") do
            h2(class: "text-lg font-medium text-slate-900") { I18n.t("design.editor.document_styles") }
            div(class: "flex flex-col gap-2") do
              @paragraph_styles.each { |style| document_style_row(style) }
            end
          end
        end

        def document_style_row(style)
          RubyUI::Card(class: "p-3 flex items-center justify-between gap-3") do
            div(class: "flex items-center gap-2 flex-wrap") do
              span(class: "font-medium text-slate-900") { style.name }
              span(class: "text-sm text-slate-500") do
                plain "— #{style.font || "inherit"}, #{style.font_size || "inherit"}pt"
              end
            end
            a(
              href: helpers.edit_theme_paper_size_document_design_paragraph_style_path(@theme, @paper_size, @document_design, style),
              class: "text-sm font-medium text-blue-600 hover:underline"
            ) { I18n.t("design.shared.edit") }
          end
        end

        def base_styles_section
          section(class: "flex flex-col gap-3") do
            h2(class: "text-lg font-medium text-slate-900") { I18n.t("design.editor.base_text_styles") }
            p(class: "text-sm text-slate-500") do
              plain "#{I18n.t("design.editor.shared_styles_sentence")} "
              strong do
                a(href: helpers.theme_path(@theme), class: "text-blue-600 hover:underline") { I18n.t("design.editor.theme_page") }
              end
              plain "."
            end
            div(class: "flex flex-col gap-2") do
              @theme.base_paragraph_styles.order(:name).each { |style| base_style_row(style) }
            end
          end
        end

        def base_style_row(style)
          RubyUI::Card(class: "p-3 flex items-center justify-between gap-3 opacity-70") do
            div(class: "flex items-center gap-2 flex-wrap") do
              span(class: "font-medium text-slate-900") { style.name }
              if style.korean_name.present?
                span(class: "text-sm text-slate-500") { "(#{style.korean_name})" }
              end
              span(class: "text-sm text-slate-500") do
                plain "— #{style.font || "inherit"}, #{style.font_size || "inherit"}pt"
              end
            end
            unless @theme.system?
              a(
                href: helpers.edit_theme_theme_paragraph_style_path(@theme, style),
                class: "text-sm font-medium text-blue-600 hover:underline"
              ) { I18n.t("design.shared.edit") }
            end
          end
        end
      end
    end
  end
end
