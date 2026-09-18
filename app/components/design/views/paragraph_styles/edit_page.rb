module Design
  module Views
    module ParagraphStyles
      # Full-page style editor (preview-overlay clicks): the document's
      # one-page preview on the left, the StylePanel on the right.
      class EditPage < Design::Views::Base
        def initialize(theme:, paper_size:, document_design:, style_name:, urls:, back_url:, editable: true,
                       print_preview: false)
          @theme = theme
          @paper_size = paper_size
          @document_design = document_design
          @style_name = style_name
          @urls = urls
          @back_url = back_url
          @editable = editable
          @print_preview = print_preview
        end

        def view_template
          shell(title: @style_name, action_slot: nil, sidebar: sidebar) do
            div(class: "px-6 py-8") do
              div(class: "flex flex-col lg:flex-row lg:items-start gap-6") do
                # Sticky so the preview stays in view while the (tall) panel scrolls the page.
                # Page 1 only: this page is about one style, not the whole document.
                div(class: "flex-1 min-w-0 lg:sticky lg:top-6 lg:self-start") do
                  render Design::Views::DocumentDesigns::PreviewSection.new(
                    theme: @theme, document_design: @document_design, print_preview: @print_preview,
                    preview_url: helpers.preview_theme_paper_size_document_design_path(@theme, @paper_size, @document_design,
                                                                                       preview_mode: "single"))
                end
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
      end
    end
  end
end
