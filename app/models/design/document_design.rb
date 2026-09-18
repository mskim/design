module Design
  class DocumentDesign < Design::ApplicationRecord
    self.table_name = "design_document_designs"

    belongs_to :paper_size, class_name: "Design::PaperSize"
    has_one :theme, through: :paper_size
    has_many :paragraph_styles, as: :styleable, class_name: "Design::ParagraphStyle", dependent: :destroy
    has_many :heading_elements, -> { order(:position) }, class_name: "Design::HeadingElement", dependent: :destroy
    has_one_attached :heading_bg_image

    accepts_nested_attributes_for :heading_elements, allow_destroy: true

    validates :doc_type, presence: true, uniqueness: { scope: :paper_size_id }

    after_create { Design::DefaultGenerator.call_for(self) }

    COVER_TYPES = %w[single_any_side single_left single_right spread back_to_back].freeze
    validates :cover_type, inclusion: { in: COVER_TYPES }, if: :has_document_cover?

    COPYRIGHT_DEFAULTS = { text_box_anchor_position: 7, text_box_grid_width: 4, text_box_grid_height: 6 }.freeze

    SINGLE_PAGE_TYPES = %w[title_page blank_page copyright inside_cover part_cover document_cover thanks dedication].freeze
    MULTI_PAGE_TYPES = %w[foreword prologue toc chapter poem appendix epilogue help information].freeze
    COVER_PANEL_TYPES = %w[front_page back_page seneca front_wing back_wing].freeze
    # Physical left→right order of the panels across the assembled book-cover spread
    # (back wing | back page | spine | front page | front wing). Used to display the
    # cover section in the same order the panels sit on the printed cover.
    COVER_PANEL_ORDER = %w[back_wing back_page seneca front_page front_wing].freeze
    WING_PANEL_TYPES = %w[front_wing back_wing].freeze
    ALL_DOC_TYPES = (SINGLE_PAGE_TYPES + MULTI_PAGE_TYPES + COVER_PANEL_TYPES).freeze

    LOGO_POSITIONS = %w[left center right].freeze
    validates :logo_position, inclusion: { in: LOGO_POSITIONS }, allow_nil: true
    validates :image_opacity, numericality: { only_integer: true, in: 0..100 }, allow_nil: true

    PHOTO_FITS = %w[cover contain].freeze
    validates :photo_fit, inclusion: { in: PHOTO_FITS }, allow_blank: true
    validates :photo_grid_width,  numericality: { only_integer: true, in: 1..6 },  allow_nil: true
    validates :photo_grid_height, numericality: { only_integer: true, in: 1..12 }, allow_nil: true
    validates :photo_anchor,      numericality: { only_integer: true, in: 1..9 },  allow_nil: true
    validates :photo_border_width, numericality: { greater_than_or_equal_to: 0 },  allow_nil: true

    # Canonical reading order (frontmatter → bodymatter → rearmatter) for displaying
    # a paper size's document designs. doc_types not listed sort to the end.
    DOC_TYPE_ORDER = %w[
      title_page copyright inside_cover dedication thanks foreword prologue information help toc
      part_cover document_cover chapter poem
      epilogue appendix
    ].freeze

    def self.by_reading_order(designs)
      designs.sort_by { |dd| DOC_TYPE_ORDER.index(dd.doc_type) || DOC_TYPE_ORDER.length }
    end

    def self.interior_for(paper_size)
      by_reading_order(paper_size.document_designs.where.not(doc_type: COVER_PANEL_TYPES))
    end

    # Reading-matter groups for the theme show page (mirrors book_design's grouping).
    FRONTMATTER = %w[title_page inside_cover blank_page copyright toc foreword prologue dedication thanks information].freeze
    BODYMATTER  = %w[chapter poem part_cover document_cover].freeze
    REARMATTER  = %w[epilogue appendix help].freeze

    # Partition designs into ordered matter groups; doc_types in none land in :other.
    def self.grouped_by_matter(designs)
      ordered = by_reading_order(designs)
      {
        frontmatter: ordered.select { |dd| FRONTMATTER.include?(dd.doc_type) },
        bodymatter:  ordered.select { |dd| BODYMATTER.include?(dd.doc_type) },
        rearmatter:  ordered.select { |dd| REARMATTER.include?(dd.doc_type) },
        cover:       designs.select { |dd| COVER_PANEL_TYPES.include?(dd.doc_type) }
                            .sort_by { |dd| COVER_PANEL_ORDER.index(dd.doc_type) },
        other:       ordered.reject { |dd| (FRONTMATTER + BODYMATTER + REARMATTER + COVER_PANEL_TYPES).include?(dd.doc_type) }
      }
    end

    DEFAULT_HEADING_ELEMENTS = {
      "inside_cover" => %w[title subtitle author publisher],
      "part_cover" => %w[title subtitle],
      "document_cover" => %w[title subtitle],
      "blank_page" => [],
      "copyright" => [],
      # Cover panel types
      "front_page" => %w[title subtitle author publisher],
      "back_page" => [],
      "seneca" => %w[title author publisher],
      "front_wing" => [],
      "back_wing" => []
    }.freeze

    # Groups the theme's base styles into families, then maps each doc_type to the
    # families it actually uses, so the editor only lists relevant styles (a TOC
    # shouldn't show wing_*/cover_*/seneca_*). Theme-agnostic by naming convention;
    # review/adjust freely. Unmapped doc_types fall back to DEFAULT_STYLE_FAMILIES.
    STYLE_FAMILIES = {
      cover:   %w[cover_title cover_subtitle cover_author cover_publisher cover_body],
      seneca:  %w[seneca_title seneca_author seneca_publisher],
      heading: %w[title subtitle author h2 h3 h4 h5 h6],
      body:    %w[body blockquote quote footnote caption caption_title image_caption ol ul source],
      running: %w[header_left header_right footer_left footer_right],
      table:   %w[table_heading_cell table_body_cell]
    }.freeze

    DOC_TYPE_STYLE_FAMILIES = {
      "inside_cover"   => %i[cover],
      "part_cover"     => %i[cover],
      "document_cover" => %i[cover],
      "front_page"     => %i[cover],
      "back_page"      => %i[cover],
      "seneca"         => %i[seneca],
      "front_wing"     => %w[title body],  # wings reuse the plain title/body styles
      "back_wing"      => %w[title body],
      "toc"            => %w[title h2 h3 h4],  # heading (title) + per-level entry styles
      "title_page"     => %i[heading body],
      "dedication"     => %i[heading body],
      "thanks"         => %i[heading body],
      "copyright"      => %i[body running],
      "blank_page"     => %i[body],
      "poem"           => %i[heading body running]
    }.freeze

    # Content types (chapter, foreword, prologue, epilogue, appendix, help, information).
    DEFAULT_STYLE_FAMILIES = %i[heading body running table].freeze

    # Names of the styles relevant to this doc_type (used to scope the editor list).
    # Map entries may be family symbols (expanded via STYLE_FAMILIES) or explicit
    # style-name strings, so a doc_type can pin an exact list (e.g. toc).
    def relevant_style_names
      entries = DOC_TYPE_STYLE_FAMILIES.fetch(doc_type, DEFAULT_STYLE_FAMILIES)
      entries.flat_map { |e| e.is_a?(Symbol) ? STYLE_FAMILIES.fetch(e, []) : e }.uniq
    end

    # All other doc_types default to ["title"]
    def self.default_elements_for(doc_type)
      DEFAULT_HEADING_ELEMENTS.fetch(doc_type, %w[title])
    end

    DEFAULT_HEADING_STYLES = {
      "title" => { font_size: 18, text_align: "center", space_before: 0, space_after: 6 },
      "subtitle" => { font_size: 14, text_align: "center", space_before: 0, space_after: 4 },
      "author" => { font_size: 11, text_align: "center", space_before: 0, space_after: 4 },
      "publisher" => { font_size: 10, text_align: "center", space_before: 0, space_after: 0 }
    }.freeze

    delegate :width_mm, :height_mm, :width_pt, :height_pt,
             :left_margin_mm, :top_margin_mm, :right_margin_mm, :bottom_margin_mm,
             :left_margin_pt, :top_margin_pt, :right_margin_pt, :bottom_margin_pt,
             :binding_margin_mm, :binding_margin_pt,
             to: :paper_size

    def effective_text_box_anchor_position
      text_box_anchor_position || (doc_type == "copyright" ? COPYRIGHT_DEFAULTS[:text_box_anchor_position] : nil)
    end

    def effective_text_box_grid_width
      text_box_grid_width || (doc_type == "copyright" ? COPYRIGHT_DEFAULTS[:text_box_grid_width] : nil)
    end

    def effective_text_box_grid_height
      text_box_grid_height || (doc_type == "copyright" ? COPYRIGHT_DEFAULTS[:text_box_grid_height] : nil)
    end

    def effective_toc_v_align
      toc_v_align || "bottom"
    end

    def body_line_count
      self[:body_line_count] || paper_size.body_line_count
    end

    def body_line_count_overridden?
      self[:body_line_count].present?
    end

    def body_line_height
      content_height_pt / body_line_count
    end

    def content_width_pt(side: :single)
      base = width_pt - left_margin_pt - right_margin_pt
      base -= binding_margin_pt if side != :single
      base
    end

    def content_height_pt
      height_pt - top_margin_pt - bottom_margin_pt
    end

    def heading_height_pt
      (heading_height_in_lines || 0) * body_line_height
    end

    def column_width_pt(side: :single)
      (content_width_pt(side: side) - (column_count - 1) * gutter) / column_count
    end

    def single_page?
      SINGLE_PAGE_TYPES.include?(doc_type)
    end

    # Populate heading elements based on doc_type defaults.
    # Also ensures corresponding paragraph styles exist.
    def populate_default_heading_elements
      return if heading_elements.any?

      element_types = self.class.default_elements_for(doc_type)
      element_types.each_with_index do |etype, idx|
        heading_elements.create!(element_type: etype, style_name: etype, position: idx)
        ensure_heading_style_exists(etype)
      end
    end

    # The chapter design on the same paper size — the parent of every other
    # doc type's styles. nil for chapter itself.
    def chapter_design
      return nil if doc_type == "chapter"
      paper_size.document_designs.find_by(doc_type: "chapter")
    end

    # Resolved style values this design inherits for `name` (its parent):
    # theme base for chapter; theme base → chapter for other doc types.
    def parent_values(name)
      layer = values_of(theme.base_paragraph_styles.find_by(name: name))
      if (ch = chapter_design) && (ch_row = ch.paragraph_styles.find_by(name: name))
        layer = overlay(layer, values_of(ch_row))
      end
      layer
    end

    # Resolve theme base → chapter (same paper size) → this doc type, field by
    # field (nil falls back to the layer below), like book_write's renderer.
    # Returned styles are read-only; do not mutate — a style present on a single
    # layer is that layer's persisted row (e.g. chapter's row, seen from foreword).
    def merged_paragraph_styles
      base_styles = theme.base_paragraph_styles.index_by(&:name)
      chapter = chapter_design
      chapter_rows = chapter ? chapter.paragraph_styles.index_by(&:name) : {}
      own_rows = paragraph_styles.index_by(&:name)
      (base_styles.keys | chapter_rows.keys | own_rows.keys).map do |n|
        layers = [ base_styles[n], chapter_rows[n], own_rows[n] ].compact
        layers.drop(1).reduce(layers.first) { |acc, row| merge_style(acc, row) }
      end
    end

    # Returns (creating if needed) this design's sparse row for a style: every
    # field nil, so it inherits until a field is set. Kept for callers not yet
    # migrated to the field-level operations.
    def override_for(base_name) = paragraph_styles.find_or_create_by!(name: base_name)

    # Create or update a document-level paragraph style by name. Used by importers
    # and generators so authoritative values win over any already-present override
    # (e.g. a generator default) without tripping the (styleable, name) uniqueness.
    def upsert_paragraph_style!(name, attrs = {})
      ps = paragraph_styles.find_by(name: name) || paragraph_styles.build(name: name)
      ps.update!(attrs.except(:name))
      ps
    end

    # ── Field-level style operations ─────────────────────────────────────────
    # A doc type's styles are edited once for every paper size: each operation
    # writes to this doc type's design on all of the theme's sizes, comparing
    # against that size's own parent (theme base → chapter).

    def same_doc_type_designs = theme.document_designs.where(doc_type: doc_type)

    def style_state(name)
      own = paragraph_styles.find_by(name: name)
      parent = parent_values(name)
      changed = own ? ParagraphStyle::STYLE_FIELDS.select { |f| !own[f].nil? } : []
      user = own ? changed & Array(own.overridden_fields) : []
      { own: own, parent_values: parent, changed_fields: changed, user_fields: user,
        has_parent: parent.values.any? { |v| !v.nil? } }
    end

    class MissingChapterError < StandardError; end

    # Set `field` of style `name` (edited on this size) on every size.
    # A blank value reverts the field everywhere; so does, for doc types other
    # than chapter, a value equal to THIS size's parent. Otherwise this size gets
    # `value` exactly; other sizes get a proportional value for SCALED_FIELDS
    # (their current × value / this size's current) and the same value for every
    # other field. Wherever the target equals that size's own parent the field is
    # cleared (inherit), never marked. Chapter keeps the per-size path even when
    # the value equals its parent: chapter rows carry the per-size scaled values
    # every other doc type inherits, so returning one size to the theme base
    # must scale the others rather than wipe them.
    def set_style_field!(name, field, value)
      assert_style_field!(field)
      field = field.to_s
      value = value.strip if value.is_a?(String)
      parent = parent_values(name)
      if value.nil? || value == "" ||
         (doc_type != "chapter" && ParagraphStyle.inherits_value?(field, value, parent[field]))
        return revert_style_field!(name, field)
      end

      ref = resolved_field(name, field, parent)
      # A scaled field set to its current value scales the other sizes by 1:
      # nothing changes there, so leave them (and their marks) alone.
      unchanged_elsewhere = ParagraphStyle::SCALED_FIELDS.include?(field) &&
                            ParagraphStyle.same_value?(field, value, ref)
      transaction do
        same_doc_type_designs.find_each do |dd|
          next if dd.id != id && unchanged_elsewhere
          dd_parent = dd.id == id ? parent : dd.parent_values(name)
          target = dd.id == id ? value : cross_size_value(field, value, ref, dd.resolved_field(name, field, dd_parent))
          if ParagraphStyle.inherits_value?(field, target, dd_parent[field])
            dd.clear_style_field(name, field, has_parent: dd_parent.values.any? { |v| !v.nil? })
          else
            row = dd.paragraph_styles.find_or_initialize_by(name: name)
            row[field] = target
            row.overridden_fields = (Array(row.overridden_fields) | [ field ])
            row.save!
          end
        end
        touch_inheritors!
      end
    end

    def revert_style_field!(name, field)
      assert_style_field!(field)
      field = field.to_s
      transaction do
        same_doc_type_designs.find_each { |dd| dd.clear_style_field(name, field) }
        touch_inheritors!
      end
    end

    # Delete the style's rows on every size (only where a parent exists — a
    # parentless style would vanish entirely).
    def revert_style!(name)
      transaction do
        same_doc_type_designs.find_each do |dd|
          dd.paragraph_styles.where(name: name).destroy_all if dd.style_has_parent?(name)
        end
        touch_inheritors!
      end
    end

    # For each user field a push would move up, the number of sibling doc types
    # that keep their own value for it (and so won't see the pushed value).
    def push_preview(name)
      fields = style_state(name)[:user_fields]
      siblings = doc_type == "chapter" ? theme.document_designs.where.not(doc_type: "chapter") :
                                         theme.document_designs.where.not(doc_type: [ "chapter", doc_type ])
      fields.index_with do |f|
        siblings.joins(:paragraph_styles)
                .where(design_paragraph_styles: { name: name })
                .where.not(design_paragraph_styles: { f => nil })
                .distinct.count(:doc_type)
      end
    end

    # Move the user-changed fields one layer up and clear them here. Generator-only
    # values (stored but not in overridden_fields) are never pushed.
    #
    # Chapter → theme base: this size's values become the base; each chapter size
    # then clears a pushed field only where it now equals the new base, and keeps
    # its own (per-size, e.g. proportionally scaled) value otherwise.
    #
    # Other doc types → chapter on every size: via set_style_field! on this size's
    # chapter (proportionally on the others), then the fields are reverted on
    # every size of this doc type. Every size that has this doc type must
    # therefore also have a chapter design.
    def push_style!(name)
      own = paragraph_styles.find_by(name: name) or return
      fields = style_state(name)[:user_fields]
      return if fields.empty?
      return push_style_to_theme!(name, own, fields) if doc_type == "chapter"

      assert_chapters_for_push!
      transaction do
        ch = chapter_design
        fields.each { |f| ch.set_style_field!(name, f, own[f]) }
        fields.each { |f| revert_style_field!(name, f) }
      end
    end

    def style_has_parent?(name) = parent_values(name).values.any? { |v| !v.nil? }

    protected

    # This design's current value for `field`: its own row's value, else the
    # inherited one (`parent` = parent_values(name), passed to avoid re-querying).
    def resolved_field(name, field, parent = parent_values(name))
      own = paragraph_styles.find_by(name: name)&.[](field)
      own.nil? ? parent[field] : own
    end

    def clear_style_field(name, field, has_parent: nil)
      row = paragraph_styles.find_by(name: name) or return
      row[field] = nil
      row.overridden_fields = Array(row.overridden_fields) - [ field ]
      has_parent = style_has_parent?(name) if has_parent.nil?
      if has_parent && ParagraphStyle::STYLE_FIELDS.all? { |f| row[f].nil? }
        row.destroy!
      else
        row.save!
      end
    end

    # Deleting rows doesn't bump max(updated_at); touch every design whose preview
    # may change (this doc type everywhere; for chapter, every doc type).
    def touch_inheritors!
      now = Time.current
      scope = doc_type == "chapter" ? theme.document_designs : same_doc_type_designs
      scope.update_all(updated_at: now)
      self.updated_at = now # the controller renders the preview from this instance
      clear_attribute_changes([ :updated_at ]) # already persisted by update_all
      # Rows were written/deleted through other instances; drop stale caches.
      paragraph_styles.reset
      theme.base_paragraph_styles.reset
    end

    def assert_style_field!(field)
      raise ArgumentError, "not a style field: #{field}" unless ParagraphStyle::STYLE_FIELDS.include?(field.to_s)
    end

    def assert_chapters_for_push!
      sizes = same_doc_type_designs.pluck(:paper_size_id)
      with_chapter = theme.document_designs.where(doc_type: "chapter").pluck(:paper_size_id)
      missing = sizes - with_chapter
      return if missing.empty?
      names = Design::PaperSize.where(id: missing).map(&:display_name).join(", ")
      raise MissingChapterError, "no chapter design on #{names}"
    end

    private

    def push_style_to_theme!(name, own, fields)
      transaction do
        base = theme.base_paragraph_styles.find_or_initialize_by(name: name)
        fields.each { |f| base[f] = own[f] }
        base.save!
        same_doc_type_designs.find_each do |dd|
          row = dd.paragraph_styles.find_by(name: name) or next
          fields.each do |f|
            next if row[f].nil? || !ParagraphStyle.inherits_value?(f, row[f], base[f])
            dd.clear_style_field(name, f, has_parent: true)
          end
        end
        touch_inheritors!
      end
    end

    # The value another size gets when this size's field goes ref → value.
    def cross_size_value(field, value, ref, current)
      return value unless ParagraphStyle::SCALED_FIELDS.include?(field)
      num = ->(v) { v.is_a?(Numeric) ? v.to_d : (v.is_a?(String) ? BigDecimal(v.strip, exception: false) : nil) }
      new_v, ref_v, cur_v = num.(value), num.(ref), num.(current)
      return value if new_v.nil? || ref_v.nil? || ref_v.zero? || cur_v.nil?
      (cur_v * new_v / ref_v).round(2)
    end

    def ensure_heading_style_exists(style_name)
      defaults = DEFAULT_HEADING_STYLES[style_name]
      return unless defaults

      # Check if style already exists in merged styles
      existing = merged_paragraph_styles.find { |s| s.name == style_name }
      return if existing

      # Create on this document_design with heading font from theme
      heading_font = theme&.base_heading_font
      paragraph_styles.create!(
        name: style_name,
        font: heading_font,
        **defaults
      )
    end

    MERGEABLE_ATTRS = %w[
      korean_name font font_size text_color text_align tracking space_width scale
      first_line_indent text_line_spacing space_before space_after
      space_before_in_lines space_after_in_lines left_indent right_indent
      bold_font emphasis_color
      fill_type fill_color fill_ending_color fill_gradient_direction
      border_thickness border_color border_side rounded_corners corner_radius
      padding_top padding_bottom bold_text_color emphasis_font
    ].freeze

    def merge_style(base, override)
      merged = override.dup
      MERGEABLE_ATTRS.each do |attr|
        merged[attr] = base[attr] if override[attr].nil?
      end
      merged
    end

    def values_of(row) = row ? ParagraphStyle::STYLE_FIELDS.index_with { |f| row[f] } : {}

    def overlay(lower, upper) = lower.merge(upper.compact)
  end
end
