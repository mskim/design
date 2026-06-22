module Design
  module Views
    module ParagraphStyles
      class Panel < Design::Views::Base
        register_element :turbo_frame

        def initialize(paragraph_style:, panel_update_url:, back_url:, revert_url: nil, editable: true)
          @paragraph_style = paragraph_style
          @panel_update_url = panel_update_url
          @back_url = back_url
          @revert_url = revert_url
          @editable = editable
        end

        def view_template
          turbo_frame(id: "properties_panel") do
            div(class: "design-studio flex flex-col gap-3 p-4 max-h-[80vh] overflow-y-auto") do
              render_header
              render_errors if @paragraph_style.errors.any?
              render_form
            end
          end
        end

        private

        def render_header
          div(class: "flex items-center justify-between") do
            h2(class: "text-base font-semibold text-slate-900") { @paragraph_style.name.presence || "New Style" }
            a(
              href: @back_url,
              data: { turbo_frame: "_top" },
              class: "text-sm text-blue-600 hover:underline"
            ) { "← Back" }
          end
        end

        def render_errors
          div(class: "rounded border border-red-300 bg-red-50 p-3") do
            p(class: "text-sm font-medium text-red-800 mb-1") { "Please fix the following errors:" }
            ul(class: "list-disc list-inside space-y-0.5") do
              @paragraph_style.errors.full_messages.each do |msg|
                li(class: "text-sm text-red-700") { msg }
              end
            end
          end
        end

        def render_form
          form(action: @panel_update_url, method: "post", class: "flex flex-col gap-5",
               data: { controller: "design--panel-autosave",
                       action: "input->design--panel-autosave#scheduleUpdate change->design--panel-autosave#scheduleUpdate submit->design--panel-autosave#save" }) do
            if @paragraph_style.persisted?
              input(type: "hidden", name: "_method", value: "patch")
            end
            input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
            render Design::Views::ParagraphStyles::Fields.new(paragraph_style: @paragraph_style, editable: @editable)
            render_actions
          end
        end

        def render_actions
          div(class: "flex items-center gap-3") do
            if @editable
              button(type: "submit", class: "inline-flex items-center rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-700") { "Save" }
              span(class: "text-xs text-slate-500 hidden", data: { "design--panel-autosave-target": "status" })
            end
            if @revert_url && @editable
              a(
                href: @revert_url,
                data: { turbo_method: :delete, turbo_frame: "properties_panel" },
                class: "text-sm text-red-600 hover:underline ml-auto"
              ) { "Revert to base" }
            end
          end
        end
      end
    end
  end
end
