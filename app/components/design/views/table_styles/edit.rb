module Design
  module Views
    module TableStyles
      class Edit < Design::Views::Base
        def initialize(theme:, table_style:)
          @theme = theme
          @table_style = table_style
        end

        def view_template
          shell(title: "#{@table_style.name.capitalize} #{I18n.t("design.table_styles.edit_suffix")}", action_slot: nil, sidebar: nil) do
            div(class: "flex flex-col lg:flex-row gap-6 px-6 py-8") do
              preview_pane
              form_pane
            end
          end
        end

        private

        def preview_pane
          div(class: "flex-1 min-w-0 flex items-start justify-center rounded-lg border border-slate-200 bg-slate-50 p-4") do
            if Design.config.table_style_preview
              turbo_frame_tag("preview_frame") do
                img(src: helpers.preview_theme_table_style_path(@theme, @table_style, t: @table_style.updated_at.to_i),
                    alt: @table_style.name, class: "max-w-full border border-slate-200 bg-white shadow-sm")
              end
            else
              div(class: "py-16 text-sm text-slate-400") { I18n.t("design.table_styles.no_preview") }
            end
          end
        end

        def form_pane
          div(class: "lg:w-96 lg:shrink-0 flex flex-col rounded-lg border border-slate-200 bg-white") do
            render Design::Views::TableStyles::Form.new(theme: @theme, table_style: @table_style)
            reset_form
          end
        end

        def reset_form
          div(class: "border-t border-slate-200 px-4 py-3") do
            form(action: helpers.reset_theme_table_style_path(@theme, @table_style), method: "post") do
              input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
              button(type: "submit",
                     class: "px-3 py-1.5 rounded-md text-xs font-medium border border-amber-300 text-amber-700 hover:bg-amber-50",
                     data: { turbo_confirm: I18n.t("design.table_styles.reset_confirm") }) { I18n.t("design.table_styles.reset") }
            end
          end
        end
      end
    end
  end
end
