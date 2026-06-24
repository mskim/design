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
    end
  end
end
