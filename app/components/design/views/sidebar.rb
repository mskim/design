module Design
  module Views
    # Left rail for every studio page inside a theme: theme + paper size selects on
    # top, then (for editable themes) the size actions — new size, size settings,
    # generate other sizes — then the book tree, as book_write's 디자인수정 tree: 책 전체
    # (the theme overview for the size) alone on top, the structure's sections
    # (표지/머리/본문/꼬리, the studio's existing matter labels; cover first like
    # bookcheego's tree) each folding under a chevron, one leaf per doc_type design, and
    # finally the theme's table styles section.
    # On a read-only theme the structure is listed as plain text (spans, no links):
    # every editor action answers 403 there (ApplicationController#ensure_theme_editable).
    # Rendered into Shell's sidebar: slot via Base#theme_sidebar.
    #
    # size_url: ->(paper_size) { url } — the URL of *this page kind* for another
    # size, so changing the size select keeps the designer on the same page.
    # Defaults to the theme overview for that size.
    #
    # current: { kind:, id: } — which leaf to highlight: :theme (책 전체, the theme
    # overview), :paper_size (size settings), :document_design / :table_style with an id.
    # ids must be Integers (compared with == against record ids).
    class Sidebar < Design::Views::Base
      def initialize(theme:, paper_size:, current: nil, size_url: nil)
        @theme = theme
        @paper_size = paper_size
        @current = current
        @size_url = size_url
      end

      def view_template
        nav(class: "flex flex-col gap-3 p-3 text-sm", aria_label: "Studio",
            data: { controller: "design--book-tree", "design--book-tree-open-value": open_matter_keys.join(",") }) do
          theme_select
          size_select if @theme.paper_sizes.any? # a theme with no sizes gets just "new size"
          size_links if editable?
          book_tree
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

      LINK_BASE    = "block truncate rounded px-2 py-0.5 no-underline"
      LINK_CLASS   = "#{LINK_BASE} text-blue-600 hover:bg-slate-200"
      ACTIVE_CLASS = "#{LINK_BASE} bg-slate-900 text-white"

      # Memoized: called once per leaf.
      def editable?
        @editable = @theme.editable_by?(Design.current_user) if @editable.nil?
        @editable
      end

      def theme_select
        labelled_select("theme", I18n.t("design.sidebar.theme")) do
          Design::Theme.starter_themes.order(:name).each do |t|
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
            size_settings_link
            li { generate_sizes_button }
          end
        end
      end

      def size_settings_link
        active = current?(:paper_size)
        li do
          a(href: helpers.edit_theme_paper_size_path(@theme, @paper_size), class: active ? ACTIVE_CLASS : LINK_CLASS,
            aria_current: (active ? "page" : nil)) { I18n.t("design.sidebar.size_settings") }
        end
      end

      # Moved from Themes::Show#generate_sizes_button (same route). That button used
      # data-turbo="false" + data-confirm, but with Turbo disabled and no Rails UJS loaded
      # (Importmaps + Turbo only) data-confirm never fired — the old confirm was dead. Here
      # we deliberately drop turbo: false and use turbo_confirm so the confirm actually
      # works; the controller's redirect is fine under Turbo. A plain form rather than
      # button_to: phlex-rails' button_to goes through view_context, which is nil when the
      # component is rendered bare in tests (Themes::Show#clone_button uses the same shape).
      def generate_sizes_button
        form(action: helpers.generate_sizes_theme_path(@theme), method: "post",
             data: { turbo_confirm: I18n.t("design.themes.generate_sizes_confirm") }) do
          input(type: "hidden", name: "authenticity_token", value: helpers.form_authenticity_token)
          button(type: "submit", class: "px-2 py-0.5 text-left text-xs text-blue-600 hover:underline") do
            I18n.t("design.themes.generate_sizes", size: @theme.default_paper_size&.display_name)
          end
        end
      end

      # The book tree, in book_write's 디자인수정 look (its book_tree.css classes, ported to
      # app/assets/tailwind/design.css): 책 전체 alone on top, then one section per matter
      # group with a chevron fold toggle, then the table styles.
      def book_tree
        div(class: "book-tree studio-tree") do
          if @paper_size
            whole_book
            matter_groups
          end
          table_styles_group
        end
      end

      # 책 전체: the theme overview for this size. The overview is open on read-only themes
      # too, so this is always a link.
      def whole_book
        ul(class: "book-tree__items studio-tree__book") do
          li(class: "book-tree__item") do
            div(class: "book-tree__row") do
              tree_link(I18n.t("design.sidebar.whole_book"), helpers.theme_path(@theme, paper_size_id: @paper_size.id),
                        current: current?(:theme))
            end
          end
        end
      end

      def matter_groups
        grouped = Design::DocumentDesign.grouped_by_matter(@paper_size.document_designs.to_a)
        MATTER_ORDER.each do |group, key|
          designs = grouped[group]
          next if designs.blank?
          matter_section(group.to_s, I18n.t(key), pinned: holds_current?(designs)) do
            designs.each { |dd| leaf(doc_type_label(dd.doc_type), design_href(dd), active: current?(:document_design, dd.id)) }
          end
        end
      end

      # Not a matter group: always rendered open, and folding it is not remembered.
      def table_styles_group
        styles = @theme.table_styles.defaults.order(:name).to_a
        return if styles.empty?
        tree_section(I18n.t("design.sidebar.table_styles"), open: true, data: { tree_group: "table_styles" }) do
          styles.each do |ts|
            leaf(ts.name.capitalize, helpers.edit_theme_table_style_path(@theme, ts), active: current?(:table_style, ts.id))
          end
        end
      end

      # A section of the tree: a header row whose toggle button (label + chevron) folds the
      # list below it. Folded is aria-expanded="false"; the stylesheet hides the list after it
      # (.book-tree__row:has(... [aria-expanded=false]) + .book-tree__items), as in book_write.
      def tree_section(label_text, open:, **attrs, &leaves)
        section(class: "book-tree__section", **attrs) do
          div(class: "book-tree__row book-tree__row--section") do
            button(type: "button", class: "book-tree__toggle", aria_expanded: open.to_s,
                   data: { action: "design--book-tree#toggle" }) do
              span(class: "book-tree__section-label") { label_text }
              span(class: "book-tree__chevron", aria_hidden: "true")
              span(class: "sr-only") { I18n.t("design.sidebar.toggle") }
            end
          end
          ul(class: "book-tree__items", &leaves)
        end
      end

      # A matter group is open when this browser left it open (the book-tree cookie).
      # The group holding the current design is pinned open so its active leaf shows;
      # design--book-tree does not save that pinned opening in the cookie.
      def matter_section(matter, label_text, pinned:, &leaves)
        saved_open = open_matter_keys.include?(matter)
        tree_section(label_text, open: pinned || saved_open,
                     data: { matter: matter, pinned_open: (pinned && !saved_open) || nil }, &leaves)
      end

      def holds_current?(designs)
        designs.any? { |dd| current?(:document_design, dd.id) }
      end

      # Read-only theme: plain text, nothing navigable (so current highlighting is moot).
      def leaf(label_text, href, active:)
        li(class: "book-tree__item") do
          div(class: "book-tree__row") do
            if editable?
              tree_link(label_text, href, current: active)
            else
              span(title: label_text, class: "book-tree__link") { label_text }
            end
          end
        end
      end

      def tree_link(label_text, href, current:)
        a(href: href, title: label_text, class: [ "book-tree__link", ("is-current" if current) ],
          aria_current: (current ? "page" : nil)) { label_text }
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
