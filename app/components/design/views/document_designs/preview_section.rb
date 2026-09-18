module Design
  module Views
    module DocumentDesigns
      # The preview column of the design editor and the full-page style editor:
      # title, 안내선 / 인쇄용 toggles, the sample-content link and the lazy
      # #preview_frame. The toggles sit OUTSIDE the frame, so they survive every
      # frame replacement (live preview, saves). design--preview-toolbar keeps
      # 안내선 as data-guides on this element (Preview's guide layers hide under
      # "off") and 인쇄용 as the design_preview_print cookie; print_preview is
      # that cookie, read by the controller.
      class PreviewSection < Design::Views::Base
        register_element :turbo_frame

        TOGGLE = "rounded border border-slate-300 bg-white px-2 py-0.5 text-xs text-slate-600 " \
                 "aria-pressed:border-slate-900 aria-pressed:bg-slate-900 aria-pressed:text-white disabled:opacity-50".freeze

        def initialize(theme:, document_design:, preview_url:, print_preview: false)
          @theme = theme
          @document_design = document_design
          @preview_url = preview_url
          @print_preview = print_preview
        end

        def view_template
          div(class: "group/preview rounded-lg border border-slate-200 bg-slate-50 p-4",
              data: { controller: "design--preview-toolbar", guides: "on",
                      "design--preview-toolbar-preview-url-value": @preview_url }) do
            div(class: "mb-2 flex flex-wrap items-center justify-between gap-2") do
              h2(class: "text-sm font-medium text-slate-700") { I18n.t("design.editor.preview") }
              div(class: "flex items-center gap-2") do
                toggle("guides", I18n.t("design.preview.guides"), pressed: true)
                toggle("print", I18n.t("design.preview.print"), pressed: print_on?,
                       disabled: !@document_design.binding_applies?,
                       title: (I18n.t("design.preview.print_unavailable") unless @document_design.binding_applies?))
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

        def print_on? = @print_preview && @document_design.binding_applies?

        def toggle(name, label, pressed:, disabled: false, title: nil)
          action = name == "guides" ? "toggleGuides" : "togglePrint"
          button(type: "button", class: TOGGLE, title: title, disabled: (true if disabled),
                 aria: { pressed: pressed.to_s },
                 data: { "design--preview-toolbar-target": name, action: "design--preview-toolbar##{action}" }) { label }
        end
      end
    end
  end
end
