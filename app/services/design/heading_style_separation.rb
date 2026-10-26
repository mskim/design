require "sqlite3"

module Design
  # The one-off data step that gives the title-page kinds their own title,
  # subtitle, author and publisher (spec 2026-10-26 §6).
  #
  # Before it, those kinds resolved the four through chapter (theme → chapter →
  # kind), and the host renamed them to h1/h2/h3/body for the title-page
  # layout. After it they resolve theme → kind (DocumentDesign#skips_chapter?)
  # and print by their own names. So, once per theme, what each kind printed
  # is copied onto its own rows:
  #
  # 1. Every printed value is computed first, in render terms (the host's
  #    ThemeStyleLayers.resolve): field by field over MERGEABLE_ATTRS, theme →
  #    chapter → kind, a nil or blank field inheriting, dropcap skipping
  #    chapter. title, subtitle and author print their own resolved style;
  #    publisher its own, else body's without the fields the heading stack
  #    doesn't read (BODY_ONLY). publisher is the one name that gains a parent
  #    (step 4's row), so where it printed a seeded field from nothing, the
  #    value the host printed for nothing is written instead (RENDER_DEFAULTS).
  # 2. Each kind's design gets the row if it has none (a raw INSERT naming
  #    every column, so the table's defaults don't stick), and every nil or
  #    blank field takes the printed value; set fields are kept.
  # 3. In records, font_size alone is marked overridden (the one field
  #    DefaultGenerator checks, which now writes title pages' sizes too).
  # 4. The theme-level publisher row is inserted last: body's font, size and
  #    colour, centred, every other field NULL. It also marks a theme as done:
  #    a theme (or .db) that has it is skipped, so a field set back to inherit
  #    later never gets the chapter's value again.
  # 5. The designs are touched, so previews refresh.
  #
  # Plain SQL, in two stores with the same shape: the records
  # (design_* tables, "Design::Theme"/"Design::DocumentDesign") and a theme
  # .db (no prefix, "Theme"/"DocumentDesign", no overridden_fields, perhaps
  # missing newer columns). Called by the hosts' migrations (call_all), by
  # ThemeImportService for a file from before the change (call), by
  # ThemeStyleSeeder for a theme that has designs but no theme-level publisher
  # (call), and by book_write's .db task (call_db).
  class HeadingStyleSeparation
    KINDS = DocumentDesign::TITLE_PAGE_KINDS
    NAMES = DocumentDesign::HEADING_NAMES
    ATTRS = DocumentDesign::MERGEABLE_ATTRS
    # What publisher doesn't take from body when it falls back to it.
    BODY_ONLY = %w[korean_name space_before_in_lines space_after_in_lines first_line_indent dropcap].freeze
    PUBLISHER_SEED = %w[font font_size text_color text_align].freeze
    # What book_write prints for a style field left nil
    # (PdfGenerationService#build_style_attrs, #body_font, #body_font_size):
    # [the theme column it reads, the literal when that is NULL too].
    RENDER_DEFAULTS = { "font" => [ "base_body_font", "smShinShinMyungjoP-30" ],
                        "font_size" => [ "base_body_font_size", 9.5 ],
                        "text_color" => [ nil, "CMYK=0,0,0,100" ], "text_align" => [ nil, "justify" ] }.freeze
    # book_write renamed subtitle/author/publisher to h2/h3/body only on these
    # (its HEADING_PAGE_DOC_TYPES); title → h1 on every kind. A part cover
    # carries only a title (designcraft_rb's ChapterNumber numbers chapters
    # only), so only its title printed, and only its title is filled.
    ALIASED_KINDS = %w[title_page inside_cover].freeze

    # filled / created / skipped: one line each, for the caller to print.
    Report = Struct.new(:theme_id, :filled, :created, :skipped) do
      def to_s
        lines = [ "theme #{theme_id}: #{created.size} created, #{filled.size} filled, #{skipped.size} skipped" ]
        lines += created.map { "  created #{it}" } + filled.map { "  filled #{it}" } + skipped.map { "  skipped #{it}" }
        lines.join("\n")
      end
    end

    def self.call(theme_id) = new(RecordStore.new).call(theme_id)

    def self.call_all
      store = RecordStore.new
      store.select("SELECT id FROM design_themes ORDER BY id").map { new(store).call(it["id"]) }
    end

    # The theme in the .db at `path`.
    def self.call_db(path)
      store = DbFileStore.new(path)
      theme = store.select("SELECT id FROM themes LIMIT 1").first or raise "no theme in #{path}"
      new(store).call(theme["id"])
    ensure
      store&.close
    end

    # The theme-level publisher's seeded fields from the theme's body row and
    # the theme's own fonts (string-keyed hashes); ThemeStyleSeeder uses it too.
    def self.publisher_seed(body, theme)
      body ||= {}
      { "font" => present(body["font"]) || theme["base_body_font"],
        "font_size" => present(body["font_size"]) || theme["base_body_font_size"],
        "text_color" => present(body["text_color"]),
        "text_align" => "center" }
    end

    def self.blank?(value) = value.nil? || (value.is_a?(String) && value.strip.empty?)
    def self.present(value) = blank?(value) ? nil : value

    def initialize(store)
      @store = store
    end

    def call(theme_id)
      @report = Report.new(theme_id, [], [], [])
      if publisher_row?(theme_id)
        @report.skipped << "theme #{theme_id}: it has a theme-level publisher (already separated)"
        return @report
      end
      @columns = @store.columns(@store.styles_table) & (ATTRS + @store.legacy_fields)
      @store.transaction do
        base = styles(@store.theme_type, theme_id)
        @theme = @store.select("SELECT * FROM #{@store.themes_table} WHERE id = ?", theme_id).first || {}
        plan = printed_values(theme_id, base)     # step 1, before any write
        plan.each { |entry| apply(*entry) }         # steps 2, 3
        insert_publisher(theme_id, base)            # step 4
        touch_designs(theme_id)                     # step 5
      end
      @report
    end

    private

    def printed_values(theme_id, base)
      sizes = @store.select("SELECT id, size_name FROM #{@store.sizes_table} WHERE theme_id = ? ORDER BY id", theme_id)
      sizes.flat_map do |ps|
        designs = @store.select("SELECT id, doc_type FROM #{@store.designs_table} WHERE paper_size_id = ?", ps["id"])
                        .index_by { it["doc_type"] }
        chapter = designs["chapter"] ? styles(@store.design_type, designs["chapter"]["id"]) : {}
        KINDS.flat_map do |kind|
          unless (dd = designs[kind])
            @report.skipped << "#{ps['size_name']} (paper size #{ps['id']}): no #{kind} design"
            next []
          end
          own = styles(@store.design_type, dd["id"])
          names = ALIASED_KINDS.include?(kind) ? NAMES : %w[title]
          names.filter_map do |name|
            printed = resolve(name, base, chapter, own)
            if name == "publisher"
              printed ||= resolve("body", base, chapter, own)&.merge(BODY_ONLY.index_with(nil))
              printed &&= with_render_defaults(printed)
            end
            [ "#{ps['size_name']} #{kind} #{name}", dd["id"], name, own[name], printed ] if printed
          end
        end
      end
    end

    def with_render_defaults(printed)
      defaults = RENDER_DEFAULTS.to_h { |f, (column, literal)| [ f, self.class.present(column && @theme[column]) || literal ] }
                                .slice(*@columns)
      printed.merge(defaults) { |_, value, default| self.class.blank?(value) ? default : value }
    end

    # theme → chapter (without dropcap) → own, a nil or blank field inheriting.
    def resolve(name, base, chapter, own)
      layers = [ base[name], chapter[name]&.merge("dropcap" => nil), own[name] ].compact
      return if layers.empty?
      @columns.index_with { |c| layers.reverse_each.map { it[c] }.find { !self.class.blank?(it) } }
    end

    def apply(label, design_id, name, row, printed)
      row ? fill(label, row, printed) : insert(label, design_id, name, printed)
    end

    def insert(label, design_id, name, printed)
      values = { "styleable_type" => @store.design_type, "styleable_id" => design_id, "name" => name }
               .merge(printed).merge(timestamps)
      values["overridden_fields"] = marks_json([], printed["font_size"]) if @store.marks?
      insert_row(values)
      @report.created << label
    end

    def fill(label, row, printed)
      filled = @columns.select { |c| self.class.blank?(row[c]) && !self.class.blank?(printed[c]) }
      sets = filled.to_h { [ it, printed[it] ] }
      if @store.marks?
        marks = Array(JSON.parse(row["overridden_fields"].presence || "[]"))
        font_size = sets["font_size"] || self.class.present(row["font_size"])
        sets["overridden_fields"] = marks_json(marks, font_size) if font_size && !marks.include?("font_size")
      end
      return if sets.empty?
      assignments = sets.keys.map { "#{it} = ?" }.join(", ")
      @store.execute("UPDATE #{@store.styles_table} SET #{assignments}, updated_at = ? WHERE id = ?",
                     *sets.values, timestamps["updated_at"], row["id"])
      @report.filled << "#{label} (#{filled.join(', ')})" if filled.any?
    end

    def insert_publisher(theme_id, base)
      seed = self.class.publisher_seed(base["body"], @theme)
      values = { "styleable_type" => @store.theme_type, "styleable_id" => theme_id, "name" => "publisher" }
               .merge(@columns.index_with(nil)).merge(seed.slice(*@columns)).merge(timestamps)
      values["overridden_fields"] = "[]" if @store.marks?
      insert_row(values)
      @report.created << "theme-level publisher"
    end

    def touch_designs(theme_id)
      @store.execute("UPDATE #{@store.designs_table} SET updated_at = ? WHERE paper_size_id IN " \
                     "(SELECT id FROM #{@store.sizes_table} WHERE theme_id = ?)", timestamps["updated_at"], theme_id)
    end

    def insert_row(values)
      @store.execute("INSERT INTO #{@store.styles_table} (#{values.keys.join(', ')}) " \
                     "VALUES (#{([ '?' ] * values.size).join(', ')})", *values.values)
    end

    def marks_json(marks, font_size) = (font_size ? marks | [ "font_size" ] : marks).to_json

    def publisher_row?(theme_id)
      @store.select("SELECT 1 FROM #{@store.styles_table} WHERE styleable_type = ? AND styleable_id = ? AND name = 'publisher'",
                    @store.theme_type, theme_id).any?
    end

    def styles(type, id)
      @store.select("SELECT * FROM #{@store.styles_table} WHERE styleable_type = ? AND styleable_id = ?", type, id)
            .index_by { it["name"] }
    end

    def timestamps
      @timestamps ||= { "created_at" => @store.now, "updated_at" => @store.now }
    end

    # The records: the design_* tables through the host's connection.
    class RecordStore
      def themes_table = "design_themes"
      def sizes_table = "design_paper_sizes"
      def designs_table = "design_document_designs"
      def styles_table = "design_paragraph_styles"
      def theme_type = "Design::Theme"
      def design_type = "Design::DocumentDesign"
      def marks? = true
      def legacy_fields = []

      def select(sql, *binds) = connection.select_all(sanitize(sql, binds)).to_a
      def execute(sql, *binds) = connection.execute(sanitize(sql, binds))
      def columns(table) = connection.columns(table).map(&:name)
      def transaction(&) = Design::ApplicationRecord.transaction(&)
      def now = Time.current.utc.strftime("%Y-%m-%d %H:%M:%S.%6N")

      private

      def connection = Design::ApplicationRecord.connection
      def sanitize(sql, binds) = Design::ApplicationRecord.sanitize_sql_array([ sql, *binds ])
    end

    # A theme .db (ThemeDbExportService's tables).
    class DbFileStore
      def initialize(path)
        @db = SQLite3::Database.new(path.to_s)
        @db.results_as_hash = true
      end

      def themes_table = "themes"
      def sizes_table = "paper_sizes"
      def designs_table = "document_designs"
      def styles_table = "paragraph_styles"
      def theme_type = ThemeDbExportService::STYLEABLE_TYPE_MAP.fetch("Design::Theme")
      def design_type = ThemeDbExportService::STYLEABLE_TYPE_MAP.fetch("Design::DocumentDesign")
      def marks? = false
      # A .db exported before D5 still has the old five border fields, which
      # book_write's ThemeStyleLayers merges and the engine reads.
      def legacy_fields = LegacyBorder::OLD_FIELDS

      def select(sql, *binds) = @db.execute(sql, binds)
      def execute(sql, *binds) = @db.execute(sql, binds)
      def columns(table) = @db.execute("PRAGMA table_info(#{table})").map { it["name"] }
      def transaction(&) = @db.transaction(&)
      def now = Time.current.utc.iso8601
      def close = @db.close
    end
  end
end
