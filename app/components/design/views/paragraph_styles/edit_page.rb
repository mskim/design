module Design
  module Views
    module ParagraphStyles
      # Full-page style editor (preview-overlay clicks): the document's
      # one-page preview on the left, the StylePanel on the right.
      class EditPage < Design::Views::Base
        register_element :turbo_frame

        def initialize(theme:, paper_size:, document_design:, style_name:, urls:, back_url:, editable: true)
          @theme = theme
          @paper_size = paper_size
          @document_design = document_design
          @style_name = style_name
          @urls = urls
          @back_url = back_url
          @editable = editable
        end

        def view_template
          shell(title: @style_name, action_slot: nil, sidebar: sidebar) do
            div(class: "px-6 py-8") do
              div(class: "flex flex-col lg:flex-row lg:items-start gap-6") do
                # Sticky so the preview stays in view while the (tall) panel scrolls the page.
                div(class: "flex-1 min-w-0 lg:sticky lg:top-6 lg:self-start") { preview_section }
                div(class: "lg:w-[28rem] lg:shrink-0") do
                  render StylePanel.new(document_design: @document_design, style_name: @style_name, urls: @urls,
                                        back_url: @back_url, back_frame: "_top", editable: @editable, preview_mode: "single")
                end
              end
            end
          end
        end

        private

        # The design highlighted; switching size opens this style on the same
        # doc type there (or that size's overview when it has none).
        def sidebar
          theme_sidebar(@theme, @paper_size, current: { kind: :document_design, id: @document_design.id },
                        size_url: ->(ps) { size_url(ps) })
        end

        def size_url(ps)
          other = ps.document_designs.find_by(doc_type: @document_design.doc_type)
          other ? helpers.theme_paper_size_document_design_style_path(@theme, ps, other, @style_name)
                : helpers.theme_path(@theme, paper_size_id: ps.id)
        end

        def preview_section
          div(class: "rounded-lg border border-slate-200 bg-slate-50 p-4") do
            div(class: "mb-2 flex items-center justify-between") do
              h2(class: "text-sm font-medium text-slate-700") { I18n.t("design.editor.preview") }
              a(href: helpers.edit_theme_sample_content_path(@theme, @document_design.doc_type, return_to: @document_design.id),
                class: "text-xs text-blue-600 hover:underline") { I18n.t("design.sample_contents.edit_link") }
            end
            # Page 1 only: this page is about one style, not the whole document.
            turbo_frame(id: "preview_frame",
                        src: helpers.preview_theme_paper_size_document_design_path(@theme, @paper_size, @document_design, preview_mode: "single"),
                        loading: "lazy") do
              div(class: "p-8 text-center text-slate-400") { I18n.t("design.editor.loading_preview") }
            end
          end
        end
      end
    end
  end
end
