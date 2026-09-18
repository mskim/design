module Design
  module Views
    module ParagraphStyles
      # The doc-type paragraph style panel (D2b). The <form> carries the
      # autosave controller and its status and is never re-rendered; the
      # server's turbo streams morph only StylePanelContent (#style-panel-content),
      # so focus, typing and an open colour popover survive a save.
      #
      # urls: { field:, style:, push:, preview: } — the style's endpoints and the
      # preview frame's GET URL (reloaded when a failed save left it stale). back_url /
      # back_frame: "← 뒤로" ("properties_panel" when embedded in the design
      # editor, "_top" on the full-page editor). preview_mode: "single" on the
      # full-page editor, so saves re-render a one-page preview.
      # content: StylePanelContent options (field_errors:, attempted:, error:).
      class StylePanel < Design::Views::Base
        register_element :turbo_frame

        ACTIONS = [
          "change->design--style-autosave#fieldChanged",
          "submit->design--style-autosave#ignoreSubmit",
          "turbo:before-morph-attribute->design--style-autosave#keepLocalState",
          "turbo:before-morph-element->design--style-autosave#keepOpenPopover"
        ].join(" ").freeze

        def initialize(document_design:, style_name:, urls:, back_url:, back_frame: "_top", editable: true,
                       preview_mode: nil, **content)
          @document_design = document_design
          @style_name = style_name
          @urls = urls
          @back_url = back_url
          @back_frame = back_frame
          @editable = editable
          @preview_mode = preview_mode
          @content = content
        end

        def view_template
          turbo_frame(id: "properties_panel") do
            div(class: "design-studio flex flex-col gap-3 p-4") do
              form(id: "style-panel-form", action: @urls[:field], method: "post", class: "flex flex-col gap-3", data: form_data) do
                input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
                top_bar
                render StylePanelContent.new(document_design: @document_design, style_name: @style_name,
                                             editable: @editable, **@content)
              end
            end
          end
        end

        private

        def top_bar
          div(class: "flex items-center justify-between") do
            a(href: @back_url, data: { turbo_frame: @back_frame }, class: "text-sm text-blue-600 hover:underline") { I18n.t("design.panel.back") }
            span(class: "text-xs text-slate-500 data-[status=error]:text-red-600", role: "status", aria: { live: "polite" },
                 data: { "design--style-autosave-target": "status" })
          end
        end

        def form_data
          {
            controller: "design--style-autosave",
            turbo: "false",
            action: ACTIONS,
            "design--style-autosave-field-url-value": @urls[:field],
            "design--style-autosave-style-url-value": @urls[:style],
            "design--style-autosave-push-url-value": @urls[:push],
            "design--style-autosave-preview-url-value": @urls[:preview],
            "design--style-autosave-preview-mode-value": @preview_mode,
            "design--style-autosave-saving-text-value": I18n.t("design.style_panel.status.saving"),
            "design--style-autosave-saved-text-value": I18n.t("design.style_panel.status.saved"),
            "design--style-autosave-error-text-value": I18n.t("design.style_panel.status.error")
          }
        end
      end
    end
  end
end
