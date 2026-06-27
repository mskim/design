module Design
  module Views
    module ParagraphStyles
      # Full-page style editor reached by clicking a style in the document preview:
      # the document's preview on the LEFT, the style's edit form (the Panel) on the
      # RIGHT. Works for any level (document/theme/paper) because the document context
      # comes from the panel route, so even a theme-inherited style shows the preview.
      class EditPage < Design::Views::Base
        register_element :turbo_frame

        def initialize(paragraph_style:, theme:, paper_size:, document_design:, panel_update_url:, back_url:, revert_url: nil, editable: true)
          @paragraph_style = paragraph_style
          @theme = theme
          @paper_size = paper_size
          @document_design = document_design
          @panel_update_url = panel_update_url
          @back_url = back_url
          @revert_url = revert_url
          @editable = editable
        end

        def view_template
          shell(title: @paragraph_style.name, action_slot: nil, sidebar: nil) do
            div(class: "mx-auto max-w-6xl px-6 py-10") do
              div(class: "flex flex-col lg:flex-row gap-6") do
                div(class: "flex-1 min-w-0") { preview_section }
                div(class: "lg:w-[28rem] lg:shrink-0") do
                  render Design::Views::ParagraphStyles::Panel.new(
                    paragraph_style: @paragraph_style,
                    panel_update_url: @panel_update_url,
                    back_url: @back_url,
                    revert_url: @revert_url,
                    editable: @editable
                  )
                end
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
