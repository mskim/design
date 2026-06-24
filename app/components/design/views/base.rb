module Design
  module Views
    class Base < Phlex::HTML
      include Phlex::Rails::Helpers::Routes
      include Phlex::Rails::Helpers::ButtonTo
      include Phlex::Rails::Helpers::TurboFrameTag
      include RubyUI

      # Render the host-registered actions for a slot. The block is re-bound to the
      # view context so host routes (main_app.*) resolve at render time.
      def render_host_actions(slot, context = nil)
        block = Design.config.actions.resolve(slot) or return
        Array(helpers.instance_exec(context, &block)).each { |d| render_action_descriptor(d) }
      end

      def render_action_descriptor(d)
        method = (d[:method] || :get).to_sym
        data = {}
        data[:turbo_confirm] = d[:confirm] if d[:confirm]
        if method == :get
          a(href: d[:path], class: action_button_class, data: data) { d[:label] }
        else
          button_to(d[:label], d[:path], method: method, class: action_button_class, data: data)
        end
      end

      # Shared button styling — refined to match book_design's action buttons in a later task.
      def action_button_class = "inline-flex items-center gap-1 rounded-md px-3 py-1.5 text-sm font-medium border border-slate-300 hover:bg-slate-50"

      # Localized label for a doc_type (falls back to the raw key for unmapped types).
      def doc_type_label(doc_type) = I18n.t("design.doc_types.#{doc_type}", default: doc_type)

      # Generate (cached) the preview for a document design and emit an <img>; if
      # generation fails or args are missing, yield the fallback block (e.g. a
      # placeholder). Generation shells out to PreviewService (matches book_design's
      # generate-on-render); the PreviewService fingerprint cache skips unchanged designs.
      # No `t:` cache-buster — stable JPG URL (browser caches; a fingerprint buster is a
      # deferred perf follow-up).
      def design_preview_img(theme, paper_size, document_design, img_class:, &fallback)
        ok = paper_size && document_design &&
             Design::PreviewService.new(document_design, paper_size: paper_size).generate[:success]
        if ok
          img(src: helpers.preview_jpg_theme_paper_size_document_design_path(theme, paper_size, document_design),
              alt: document_design.doc_type, class: img_class)
        elsif fallback
          fallback.call
        end
      end

      # Studio chrome convenience. The body block must be passed to render(...) and
      # consumed via yield inside Shell#view_template — a block stored at .new and
      # invoked later renders nothing in Phlex 2.4.1.
      def shell(**opts, &block) = render(Design::Views::Shell.new(**opts), &block)
    end
  end
end
