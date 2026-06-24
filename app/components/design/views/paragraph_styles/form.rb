module Design
  module Views
    module ParagraphStyles
      class Form < Design::Views::Base
        register_element :turbo_frame

        def initialize(paragraph_style:, form_url:, cancel_url:, crumbs:, document_design: nil, paper_size: nil, theme: nil)
          @paragraph_style = paragraph_style
          @form_url = form_url
          @cancel_url = cancel_url
          @crumbs = crumbs
          @document_design = document_design
          @paper_size = paper_size
          @theme = theme
        end

        def view_template
          div(class: "design-studio mx-auto max-w-6xl px-6 py-10 flex flex-col gap-8") do
            render Design::Views::Breadcrumb.new(crumbs: @crumbs)

            h1(class: "text-2xl font-semibold text-slate-900") { @paragraph_style.name }

            div(class: "flex flex-col lg:flex-row gap-6") do
              div(class: "flex-1 min-w-0") { form_section }
              if @document_design
                div(class: "lg:w-[28rem] lg:shrink-0") { preview_section }
              end
            end
          end
        end

        private

        def form_section
          form(action: @form_url, method: "post", class: "flex flex-col gap-6") do
            input(type: "hidden", name: "_method", value: "patch")
            input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)

            render Design::Views::ParagraphStyles::Fields.new(paragraph_style: @paragraph_style)

            div(class: "flex items-center gap-3") do
              button(
                type: "submit",
                class: "inline-flex items-center rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-700"
              ) { I18n.t("design.shared.save") }
              a(
                href: @cancel_url,
                class: "text-sm font-medium text-blue-600 hover:underline"
              ) { I18n.t("design.shared.cancel") }
            end
          end
        end

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
