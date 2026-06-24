module Design
  module Views
    class Shell < Design::Views::Base
      # The body block is NOT captured here — in Phlex 2.4.1 a block stored at .new
      # and invoked later renders nothing. It's passed to render(...) and consumed
      # via yield in view_template (see Base#shell).
      def initialize(title:, breadcrumb: nil, action_slot: nil, action_context: nil, sidebar: nil)
        @title = title
        @breadcrumb = breadcrumb
        @action_slot = action_slot
        @action_context = action_context
        @sidebar = sidebar
      end

      def view_template
        div(class: "design-studio flex min-h-screen flex-col") do
          top_bar
          div(class: "flex flex-1 min-h-0") do
            if @sidebar
              # Sidebar chrome copied from book_design's Pages::PaperSizes::Show
              # sidebar: w-56 border-r bg-muted/30 flex-shrink-0 (+ scroll).
              aside(class: "w-56 flex-shrink-0 overflow-y-auto border-r bg-muted/30") { render @sidebar }
            end
            main(class: "flex-1 overflow-y-auto") { yield }
          end
        end
      end

      private

      def top_bar
        # Header chrome copied from book_design's Pages::Themes::Show#render_header:
        # flex items-center justify-between, with the home link styled like its
        # "← Themes" back link (text-sm text-muted-foreground hover:text-foreground).
        header(class: "flex items-center justify-between gap-4 border-b px-6 py-4") do
          div(class: "flex items-center gap-3 min-w-0") do
            a(href: home_href, class: "design-studio__home text-sm text-muted-foreground hover:text-foreground flex-shrink-0") { I18n.t("design.themes.back_to_home") }
            span(class: "truncate text-lg font-semibold") { @breadcrumb || @title }
          end
          div(class: "flex items-center gap-2 flex-shrink-0") { render_host_actions(@action_slot, @action_context) if @action_slot }
        end
      end

      def home_href
        url = Design.config.home_url
        url ? helpers.instance_exec(&url) : helpers.themes_path
      end
    end
  end
end
