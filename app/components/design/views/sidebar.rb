module Design
  module Views
    # Left rail for every studio page inside a theme: theme + paper size selects on
    # top, then the book structure (표지/머리/본문/꼬리) with one leaf per doc_type
    # design. Rendered into Shell's sidebar: slot via Base#theme_sidebar.
    #
    # size_url: ->(paper_size) { url } — the URL of *this page kind* for another
    # size, so changing the size select keeps the designer on the same page.
    # Defaults to the theme overview for that size.
    #
    # current: { kind:, id: } — which leaf to highlight. ids must be Integers
    # (compared with == against record ids).
    class Sidebar < Design::Views::Base
      def initialize(theme:, paper_size:, current: nil, size_url: nil)
        @theme = theme
        @paper_size = paper_size
        @current = current
        @size_url = size_url
      end

      def view_template
        nav(class: "flex flex-col gap-3 p-3 text-sm", aria_label: "Studio") do
          theme_select
          size_select
          size_links if editable?
          matter_groups if @paper_size
          table_styles_group
        end
      end

      private

      SELECT_CLASS = "w-full rounded border border-slate-300 bg-white px-2 py-1 text-sm"

      # Reading order for the rail — cover first, matching bookcheego's
      # 표지/머리/본문/꼬리. (The theme overview grid is frontmatter-first on purpose;
      # do not align one to the other.)
      MATTER_ORDER = [
        [ :cover,       "design.themes.cover" ],
        [ :frontmatter, "design.themes.frontmatter" ],
        [ :bodymatter,  "design.themes.bodymatter" ],
        [ :rearmatter,  "design.themes.rearmatter" ],
        [ :other,       "design.sidebar.other" ]
      ].freeze

      LEAF_BASE    = "block truncate rounded px-2 py-0.5 no-underline"
      LEAF_CLASS   = "#{LEAF_BASE} hover:bg-slate-200"
      ACTIVE_CLASS = "#{LEAF_BASE} bg-slate-900 text-white"
      LINK_CLASS   = "#{LEAF_BASE} text-blue-600 hover:bg-slate-200"

      def editable? = @theme.editable_by?(Design.current_user)

      def theme_select
        labelled_select("theme", I18n.t("design.sidebar.theme")) do
          Design::Theme.order(:name).each do |t|
            option(value: t.id, selected: t.id == @theme.id, data: { url: helpers.theme_path(t) }) { t.name }
          end
        end
      end

      def size_select
        labelled_select("size", I18n.t("design.sidebar.size")) do
          @theme.paper_sizes.order(:id).each do |ps|
            option(value: ps.id, selected: ps.id == @paper_size&.id, data: { url: url_for_size(ps) }) { ps.display_name }
          end
        end
      end

      def labelled_select(key, label_text, &options)
        label(class: "flex flex-col gap-1") do
          span(class: "text-xs font-medium uppercase tracking-wide text-slate-500") { label_text }
          select(class: SELECT_CLASS,
                 data: { sidebar: key, controller: "design--navigate-select", action: "change->design--navigate-select#change" },
                 &options)
        end
      end

      def url_for_size(ps)
        @size_url ? @size_url.call(ps) : helpers.theme_path(@theme, paper_size_id: ps.id)
      end

      def size_links
        ul(class: "flex flex-col gap-0.5 list-none p-0") do
          li { a(href: helpers.new_theme_paper_size_path(@theme), class: LINK_CLASS) { I18n.t("design.sidebar.new_size") } }
          if @paper_size
            active = current?(:paper_size)
            li do
              a(href: helpers.edit_theme_paper_size_path(@theme, @paper_size), class: active ? ACTIVE_CLASS : LINK_CLASS,
                aria_current: (active ? "page" : nil)) { I18n.t("design.sidebar.size_settings") }
            end
            li { generate_sizes_button }
          end
        end
      end

      # Moved from Themes::Show#generate_sizes_button (same route, same confirm). A plain
      # form rather than button_to: phlex-rails' button_to goes through view_context,
      # which is nil when the component is rendered bare in tests (Themes::Show#clone_button
      # uses the same plain-form shape).
      def generate_sizes_button
        form(action: helpers.generate_sizes_theme_path(@theme), method: "post",
             data: { turbo_confirm: I18n.t("design.themes.generate_sizes_confirm") }) do
          input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
          button(type: "submit", class: "px-2 py-0.5 text-left text-xs text-blue-600 hover:underline") do
            I18n.t("design.themes.generate_sizes", size: @theme.default_paper_size&.display_name)
          end
        end
      end

      def matter_groups
        grouped = Design::DocumentDesign.grouped_by_matter(@paper_size.document_designs.to_a)
        MATTER_ORDER.each do |group, key|
          designs = grouped[group]
          next if designs.blank?
          group_box(I18n.t(key)) do
            designs.each { |dd| leaf(doc_type_label(dd.doc_type), design_href(dd), active: current?(:document_design, dd.id)) }
          end
        end
      end

      def table_styles_group
        styles = @theme.table_styles.order(:name).to_a
        return if styles.empty?
        group_box(I18n.t("design.sidebar.table_styles")) do
          styles.each do |ts|
            leaf(ts.name.capitalize, helpers.edit_theme_table_style_path(@theme, ts), active: current?(:table_style, ts.id))
          end
        end
      end

      def group_box(label_text, &leaves)
        details(open: true) do
          summary(class: "cursor-pointer select-none font-medium text-slate-700") { label_text }
          ul(class: "ml-3 mt-1 flex flex-col gap-0.5 list-none p-0", &leaves)
        end
      end

      def leaf(label_text, href, active:)
        li do
          a(href: href, title: label_text, class: active ? ACTIVE_CLASS : LEAF_CLASS,
            aria_current: (active ? "page" : nil)) { label_text }
        end
      end

      def design_href(dd)
        helpers.edit_theme_paper_size_document_design_path(@theme, @paper_size, dd)
      end

      # id omitted: true for any record of that kind (used by kind-level links such as size settings)
      def current?(kind, id = nil)
        return false unless @current && @current[:kind] == kind
        id.nil? || @current[:id] == id
      end
    end
  end
end
