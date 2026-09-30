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
        # flex items-center justify-between. The home link is an icon (the host's
        # home_icon, else a built-in house) — see #home_icon.
        header(class: "flex items-center justify-between gap-4 border-b px-6 py-4") do
          div(class: "flex items-center gap-3 min-w-0") do
            a(href: home_href, aria: { label: I18n.t("design.themes.home") }, title: I18n.t("design.themes.home"),
              class: "design-studio__home flex-shrink-0 rounded-md p-1 hover:bg-slate-100") { home_icon }
            span(class: "truncate text-lg font-semibold") { @breadcrumb || @title }
          end
          div(class: "flex items-center gap-2 flex-shrink-0") { render_host_actions(@action_slot, @action_context) if @action_slot }
        end
      end

      def home_href
        url = Design.config.home_url
        url ? helpers.instance_exec(&url) : helpers.themes_path
      end

      # The host's icon (Design.config.home_icon, a lambda evaluated in the view
      # context like home_url, returning an image URL) or a built-in house svg.
      def home_icon
        if (icon = Design.config.home_icon)
          img(src: helpers.instance_exec(&icon), alt: "", class: "h-7 w-7")
        else
          svg(xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24", fill: "none", stroke: "currentColor",
              stroke_width: "1.75", class: "h-6 w-6 text-slate-500", aria_hidden: "true") do |s|
            s.path(d: "M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z")
          end
        end
      end
    end
  end
end
