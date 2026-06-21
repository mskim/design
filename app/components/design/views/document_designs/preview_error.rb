module Design
  module Views
    module DocumentDesigns
      class PreviewError < Design::Views::Base
        register_element :turbo_frame

        def initialize(error:)
          @error = error
        end

        def view_template
          turbo_frame(id: "preview_frame") do
            div(class: "flex justify-center items-start p-8") do
              div(class: "max-w-md w-full rounded-lg border border-red-200 bg-red-50 p-4") do
                div(class: "flex items-start gap-3") do
                  span(class: "text-red-500 text-lg") { "!" }
                  div do
                    h3(class: "text-sm font-semibold text-red-800") { "Preview generation failed" }
                    p(class: "mt-1 text-xs text-red-600") { @error }
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
