module Design
  module Views
    module ParagraphStyles
      class Form < Design::Views::Base
        def initialize(paragraph_style:, form_url:, cancel_url:, crumbs:)
          @paragraph_style = paragraph_style
          @form_url = form_url
          @cancel_url = cancel_url
          @crumbs = crumbs
        end

        def view_template
          div(class: "design-studio mx-auto max-w-4xl px-6 py-10 flex flex-col gap-8") do
            render Design::Views::Breadcrumb.new(crumbs: @crumbs)

            h1(class: "text-2xl font-semibold text-slate-900") { @paragraph_style.name }

            form(action: @form_url, method: "post", class: "flex flex-col gap-6") do
              input(type: "hidden", name: "_method", value: "patch")
              input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)

              render Design::Views::ParagraphStyles::Fields.new(paragraph_style: @paragraph_style)

              div(class: "flex items-center gap-3") do
                button(
                  type: "submit",
                  class: "inline-flex items-center rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-700"
                ) { I18n.t("design.panel.save") }
                a(
                  href: @cancel_url,
                  class: "text-sm font-medium text-blue-600 hover:underline"
                ) { I18n.t("design.panel.cancel") }
              end
            end
          end
        end
      end
    end
  end
end
