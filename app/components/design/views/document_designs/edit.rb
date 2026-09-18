module Design
  module Views
    module DocumentDesigns
      class Edit < Design::Views::Base
        # tab: the properties panel's open tab (see PropertiesPanel::TABS).
        def initialize(theme:, paper_size:, document_design:, paragraph_styles:, editable: true, tab: nil,
                       print_preview: false)
          @theme = theme
          @paper_size = paper_size
          @document_design = document_design
          @paragraph_styles = paragraph_styles
          @editable = editable
          @tab = tab
          @print_preview = print_preview
        end

        def view_template
          shell(title: doc_type_label(@document_design.doc_type), action_slot: nil,
                sidebar: design_sidebar(@theme, @paper_size, @document_design)) do
            div(class: "px-6 py-8 flex flex-col gap-8") do
              render Design::Views::DocumentDesigns::EditorToolbar.new(
                theme: @theme, paper_size: @paper_size, document_design: @document_design
              )

              h1(class: "text-2xl font-semibold text-slate-900") { doc_type_label(@document_design.doc_type) }

              div(class: "flex flex-col lg:flex-row gap-6") do
                div(class: "flex-1 min-w-0") do
                  render PreviewSection.new(theme: @theme, document_design: @document_design, print_preview: @print_preview,
                                            preview_url: helpers.preview_theme_paper_size_document_design_path(@theme, @paper_size, @document_design))
                end
                div(class: "lg:w-[28rem] lg:shrink-0") { render Design::Views::DocumentDesigns::PropertiesPanel.new(theme: @theme, paper_size: @paper_size, document_design: @document_design, editable: @editable, tab: @tab) }
              end
            end
          end
        end
      end
    end
  end
end
