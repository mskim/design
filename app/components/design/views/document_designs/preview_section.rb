module Design
  module Views
    module DocumentDesigns
      # The preview column of the design editor and the full-page style editor:
      # title, 안내선 toggle, the sample-content link and the lazy
      # #preview_frame. The toggle sits OUTSIDE the frame, so it survives every
      # frame replacement (live preview, saves). design--preview-toolbar keeps
      # 안내선 as data-guides on this element (Preview's guide layers hide under
      # "off"; off until this browser turns it on). The preview itself is always in print mode (the controller's
      # preview_service) wherever the binding applies.
      class PreviewSection < Design::Views::Base
        register_element :turbo_frame

        TOGGLE = "rounded border border-slate-300 bg-white px-2 py-0.5 text-xs text-slate-600 " \
                 "aria-pressed:border-slate-900 aria-pressed:bg-slate-900 aria-pressed:text-white".freeze

        def initialize(theme:, document_design:, preview_url:)
          @theme = theme
          @document_design = document_design
          @preview_url = preview_url
        end

        def view_template
          div(class: "group/preview rounded-lg border border-slate-200 bg-slate-50 p-4",
              data: { controller: "design--preview-toolbar", guides: "off" }) do
            div(class: "mb-2 flex flex-wrap items-center justify-between gap-2") do
              h2(class: "text-sm font-medium text-slate-700") { I18n.t("design.editor.preview") }
              div(class: "flex items-center gap-2") do
                guides_toggle
                a(href: helpers.edit_theme_sample_content_path(@theme, @document_design.doc_type, return_to: @document_design.id),
                  class: "text-xs text-blue-600 hover:underline") { I18n.t("design.sample_contents.edit_link") }
              end
            end
            turbo_frame(id: "preview_frame", src: @preview_url, loading: "lazy") do
              div(class: "p-8 text-center text-slate-400") { I18n.t("design.editor.loading_preview") }
            end
          end
        end

        private

        def guides_toggle
          button(type: "button", class: TOGGLE, aria: { pressed: "false" },
                 data: { "design--preview-toolbar-target": "guides", action: "design--preview-toolbar#toggleGuides" }) do
            I18n.t("design.preview.guides")
          end
        end
      end
    end
  end
end
