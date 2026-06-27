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
      end
    end
  end
end
