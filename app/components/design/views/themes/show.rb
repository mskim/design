module Design
  module Views
    module Themes
      class Show < Design::Views::Base
        def initialize(theme:, paper_sizes:, selected_paper_size:, document_designs:)
          @theme = theme
          @paper_sizes = paper_sizes
          @selected_paper_size = selected_paper_size
          @document_designs = document_designs
        end

        def view_template
          # The selected size travels with the action context so host actions (e.g.
          # "Generate PDFs") can scope themselves to the size currently in view.
          shell(title: @theme.name, action_slot: :theme_show,
                action_context: { theme: @theme, paper_size: @selected_paper_size },
                sidebar: theme_sidebar(@theme, @selected_paper_size, current: { kind: :paper_size },
                                       size_url: ->(ps) { helpers.theme_path(@theme, paper_size_id: ps.id) })) do
            div(class: "mx-auto max-w-5xl px-6 py-10 flex flex-col gap-6") do
              header_section
              if @selected_paper_size
                doc_grid
              else
                p(class: "text-sm text-slate-500") { I18n.t("design.themes.no_custom_themes") }
              end
              table_styles_section
            end
          end
        end

        private

        def header_section
          div(class: "flex items-center justify-between gap-4") do
            div(class: "flex items-center gap-3") do
              h1(class: "text-2xl font-semibold text-slate-900") { @theme.name }
              RubyUI::Badge(variant: :slate) do
                # Key off editability, not system?: an authoring host (authoring=true)
                # can edit system themes, so "Read-only" only applies when truly locked.
                @theme.editable_by?(Design.current_user) ? I18n.t("design.themes.my_theme") : I18n.t("design.themes.read_only")
              end
            end
            div(class: "flex items-center gap-3") do
              # Cloning is the read-only consumer's path to editing; an authoring host
              # edits system themes in place, so no clone button when already editable.
              clone_button if @theme.system? && !@theme.editable_by?(Design.current_user)
              if @theme.editable_by?(Design.current_user)
                a(href: helpers.edit_theme_path(@theme)) do
                  RubyUI::Button(variant: :primary) { I18n.t("design.themes.edit_theme_button") }
                end
              end
              a(href: helpers.themes_path, class: "text-sm font-medium text-blue-600 hover:underline") do
                I18n.t("design.themes.back_to_themes")
              end
            end
          end
        end

        def clone_button
          form(action: helpers.clone_theme_path(@theme), method: "post") do
            input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
            input(type: "hidden", name: "name", value: "#{@theme.name} (Custom)")
            button(type: "submit", class: "rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white") do
              I18n.t("design.themes.clone_to_my_theme")
            end
          end
        end

        MATTER_SECTIONS = [
          [ :frontmatter, "design.themes.frontmatter" ],
          [ :bodymatter,  "design.themes.bodymatter" ],
          [ :rearmatter,  "design.themes.rearmatter" ],
          [ :cover,       "design.themes.cover" ]
        ].freeze

        # Every non-empty section is rendered; the ones whose book-tree group is closed
        # are `hidden` (design--book-tree shows/hides them as groups toggle, so no
        # reload), with a hint while nothing is visible.
        def doc_grid
          grouped = Design::DocumentDesign.grouped_by_matter(@document_designs)
          sections = MATTER_SECTIONS.filter_map do |group, key|
            [ group.to_s, key, grouped[group] ] if grouped[group].present?
          end
          turbo_frame_tag "doc_grid" do
            div(class: "flex flex-col gap-8", data: { "doc-grid": true }) do
              any_open = sections.any? { |matter, _, _| open_matter_keys.include?(matter) }
              p(class: "text-sm text-slate-500", hidden: any_open || sections.empty?, data: { "doc-grid-empty": true }) do
                I18n.t("design.themes.tree_hint")
              end
              sections.each { |matter, key, designs| matter_section(matter, key, designs) }
            end
          end
        end

        def matter_section(matter, key, designs)
          section(data: { matter: matter }, hidden: !open_matter_keys.include?(matter)) do
            h3(class: "text-sm font-medium text-muted-foreground uppercase tracking-wide mb-3") do
              I18n.t(key)
            end
            div(class: "grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-6") do
              designs.each { |dd| doc_card(dd) }
            end
          end
        end

        # Wings (flaps) and the seneca (spine) are narrower than a full page, so preview
        # their cards at a representative width rather than the page width (studio display
        # only — the real widths come from the cover in book_write).
        WING_PREVIEW_WIDTH_MM = 100
        SENECA_PREVIEW_WIDTH_MM = 10

        def doc_card(dd)
          card_width =
            if dd.doc_type == "seneca" then SENECA_PREVIEW_WIDTH_MM
            elsif Design::DocumentDesign::WING_PANEL_TYPES.include?(dd.doc_type) then WING_PREVIEW_WIDTH_MM
            else @selected_paper_size.width_mm
            end.to_i
          page_h = @selected_paper_size.height_mm.to_i
          page_w = @selected_paper_size.width_mm.to_i
          label = doc_type_label(dd.doc_type)
          div(class: "doc-card flex flex-col gap-1") do
            # Page-shaped row keeps every cover card the SAME height (the page height);
            # the thumbnail inside is the panel's true width (spine/wings narrower).
            div(class: "w-full flex justify-center", style: "aspect-ratio: #{page_w} / #{page_h};") do
              doc_thumbnail(dd, label, style: "aspect-ratio: #{card_width} / #{page_h};") do
                design_preview_img(@theme, @selected_paper_size, dd, img_class: "w-full h-full object-contain") do
                  div(class: "flex h-full w-full items-center justify-center text-xs text-slate-400") do
                    I18n.t("design.themes.no_preview")
                  end
                end
              end
            end
            span(class: "text-xs text-slate-600") { label }
          end
        end

        THUMBNAIL_CLASS = "doc-card__open block h-full max-w-full bg-white border border-slate-200 shadow-sm overflow-hidden"

        # An editable theme's thumbnail opens the page's editor (which previews the page
        # itself); a read-only theme's thumbnail is just the picture. The link breaks out
        # of the doc_grid turbo-frame — the editor is a full page with no doc_grid frame,
        # so a frame-scoped click would render "Content missing".
        def doc_thumbnail(dd, label, style:, &)
          if @theme.editable_by?(Design.current_user)
            a(href: helpers.edit_theme_paper_size_document_design_path(@theme, @selected_paper_size, dd),
              data: { turbo_frame: "_top" }, aria_label: label, style: style,
              class: "#{THUMBNAIL_CLASS} transition-colors hover:border-blue-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-400", &)
          else
            div(class: THUMBNAIL_CLASS, style: style, &)
          end
        end

        def table_styles_section
          styles = @theme.table_styles.order(:name)
          return if styles.empty?
          div(class: "flex flex-col gap-3") do
            h2(class: "text-lg font-medium text-slate-900") { I18n.t("design.table_styles.section_title") }
            div(class: "grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-3") do
              styles.each { |ts| table_style_card(ts) }
            end
          end
        end

        def table_style_card(ts)
          a(href: helpers.edit_theme_table_style_path(@theme, ts),
            class: "block rounded-lg border border-slate-200 overflow-hidden hover:shadow-md hover:border-blue-300 transition-all bg-white") do
            div(class: "aspect-[4/3] bg-slate-50 flex items-center justify-center overflow-hidden") do
              img(src: helpers.preview_theme_table_style_path(@theme, ts, t: ts.updated_at.to_i), alt: ts.name, class: "w-full h-full object-contain")
            end
            div(class: "px-3 py-2 border-t border-slate-200") do
              h3(class: "text-sm font-medium text-slate-900") { ts.name.capitalize }
              p(class: "text-xs text-slate-500") { I18n.t("design.table_styles.card_subtitle") }
            end
          end
        end

      end
    end
  end
end
