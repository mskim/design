module Design
  module Views
    class Breadcrumb < Design::Views::Base
      def initialize(crumbs:)
        @crumbs = crumbs
      end

      def view_template
        nav(class: "text-sm text-slate-500 mb-4") do
          @crumbs.each_with_index do |(label, url), index|
            plain " › " if index.positive?
            if url
              a(href: url, class: "text-blue-600 hover:underline") { label }
            else
              strong(class: "text-slate-900 font-medium") { label }
            end
          end
        end
      end
    end
  end
end
