module Design
  module Views
    module DocumentDesigns
      class EditorToolbar < Design::Views::Base
        def initialize(theme:, paper_size:, document_design:)
          @theme = theme
          @paper_size = paper_size
          @document_design = document_design
        end

        def view_template
          div(class: "flex items-center gap-1.5 text-sm") do
            a(href: helpers.theme_path(@theme),
              class: "text-slate-500 hover:text-slate-900") { @theme.name }
            span(class: "text-slate-400") { "/" }
            a(href: helpers.edit_theme_paper_size_path(@theme, @paper_size),
              class: "text-slate-500 hover:text-slate-900") { @paper_size.display_name }
            span(class: "text-slate-400") { "/" }
            doc_type_dropdown
          end
        end

        private

        def doc_type_dropdown
          div(class: "relative inline-block", data: { controller: "design--dropdown" }) do
            button(
              type: "button",
              title: I18n.t("design.document_designs.switch_doc_type"),
              class: "font-medium text-slate-900 hover:text-blue-600 flex items-center gap-1",
              data: { action: "design--dropdown#toggle" }
            ) do
              plain doc_type_label(@document_design.doc_type)
              span(class: "text-xs") { "▾" }
            end

            div(
              class: "hidden absolute left-0 top-full mt-1 bg-white border border-slate-200 rounded-md shadow-lg py-1 z-50 min-w-[180px]",
              data: { "design--dropdown-target": "menu" }
            ) do
              Design::DocumentDesign.interior_for(@paper_size).each do |dd|
                current = dd.id == @document_design.id
                a(
                  href: helpers.edit_theme_paper_size_document_design_path(@theme, @paper_size, dd),
                  class: "block px-3 py-1.5 text-sm #{current ? "bg-blue-50 text-blue-700 font-medium" : "text-slate-700 hover:bg-slate-50"}"
                ) { plain doc_type_label(dd.doc_type) }
              end
            end
          end
        end
      end
    end
  end
end
