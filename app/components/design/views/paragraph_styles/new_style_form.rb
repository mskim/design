module Design
  module Views
    module ParagraphStyles
      # 새 스타일: a name (and an optional Korean name) and 만들기. Posts inside
      # the properties_panel frame; create answers with streams.
      class NewStyleForm < Design::Views::Base
        include Design::Views::FieldGroups
        register_element :turbo_frame

        def initialize(url:, back_url:, name: nil, korean_name: nil, error: nil)
          @url = url
          @back_url = back_url
          @name = name
          @korean_name = korean_name
          @error = error
        end

        def view_template
          turbo_frame(id: "properties_panel") do
            div(class: "design-studio flex flex-col gap-3 p-4") do
              div(class: "flex items-center justify-between") do
                h2(class: "text-base font-semibold text-slate-900") { I18n.t("design.panel.new_style") }
                a(href: @back_url, data: { turbo_frame: "properties_panel" }, class: "text-sm text-blue-600 hover:underline") { I18n.t("design.panel.back") }
              end
              form(action: @url, method: "post", class: "flex flex-col gap-2") do
                input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
                field_row(I18n.t("design.fields.name")) do
                  input(type: "text", name: "name", value: @name, required: true, autofocus: true, class: CONTROL)
                end
                field_row(I18n.t("design.style_panel.korean_name_optional")) do
                  input(type: "text", name: "korean_name", value: @korean_name, class: CONTROL)
                end
                p(class: "text-sm text-red-600", role: "alert") { @error } if @error
                button(type: "submit", class: "self-end rounded bg-slate-900 px-4 py-1.5 text-sm font-medium text-white hover:bg-slate-700") do
                  I18n.t("design.style_panel.create")
                end
              end
            end
          end
        end
      end
    end
  end
end
