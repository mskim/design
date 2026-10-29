module Design
  class PaperSize < Design::ApplicationRecord
    self.table_name = "design_paper_sizes"

    belongs_to :theme, class_name: "Design::Theme"
    has_many :document_designs, class_name: "Design::DocumentDesign", dependent: :destroy
    has_many :paragraph_styles, as: :styleable, class_name: "Design::ParagraphStyle", dependent: :destroy

    include Design::Overridable
    GENERATABLE_FIELDS = %w[left_margin_mm top_margin_mm right_margin_mm bottom_margin_mm binding_margin_mm body_line_count].freeze
    before_create { capture_explicit_overrides(GENERATABLE_FIELDS) }
    after_create { Design::DefaultGenerator.call(self) }

    include Design::PageSectionFields
    PAGE_MARGIN_FIELDS = %w[top_margin_mm bottom_margin_mm left_margin_mm right_margin_mm binding_margin_mm].freeze
    WIDTH_MARGIN_FIELDS = %w[left_margin_mm right_margin_mm binding_margin_mm].freeze
    HEIGHT_MARGIN_FIELDS = %w[top_margin_mm bottom_margin_mm].freeze
    MIN_CONTENT_MM = 20

    # The sizes "copy for another size" offers. size_name follows the exported
    # themes' "<W>mmx<H>mm"; en_name is the ASCII label a non-Korean design's
    # name carries (a design's language comes from its file name).
    STANDARD_SIZES = [
      { size_name: "152mmx225mm", local_name: "신국판", en_name: "152x225", width_mm: 152, height_mm: 225 },
      { size_name: "128mmx188mm", local_name: "사륙판", en_name: "128x188", width_mm: 128, height_mm: 188 },
      { size_name: "148mmx210mm", local_name: "국판", en_name: "148x210", width_mm: 148, height_mm: 210 },
      { size_name: "176mmx248mm", local_name: "크라운판", en_name: "176x248", width_mm: 176, height_mm: 248 },
      { size_name: "188mmx257mm", local_name: "사륙배판", en_name: "188x257", width_mm: 188, height_mm: 257 },
      { size_name: "210mmx297mm", local_name: "A4", en_name: "A4", width_mm: 210, height_mm: 297 },
      { size_name: "148mmx210mm", local_name: "A5", en_name: "A5", width_mm: 148, height_mm: 210 }
    ].map(&:freeze).freeze

    # Only a Page section save asks for this (save(context: :page_section)).
    validate :page_section_margins, on: :page_section

    # A design has one size; another size is another design (SizedCopyService).
    # Checked on create only, so a legacy multi-size theme's sizes still save.
    # allow_another_size: a legacy theme's size copied as is (ThemeCloneService
    # copying every size of a theme from before), until design:single_size.
    validate :theme_has_no_size, on: :create, unless: :allow_another_size
    attr_accessor :allow_another_size

    validates :size_name, presence: true, uniqueness: { scope: :theme_id }
    validates :width_mm, :height_mm, numericality: { greater_than: 0 }
    validates :body_line_count, numericality: { greater_than: 0, only_integer: true }

    MM2PT = 2.8346456693

    def width_pt = width_mm * MM2PT
    def height_pt = height_mm * MM2PT
    def left_margin_pt = left_margin_mm * MM2PT
    def top_margin_pt = top_margin_mm * MM2PT
    def right_margin_pt = right_margin_mm * MM2PT
    def bottom_margin_pt = bottom_margin_mm * MM2PT
    def binding_margin_pt = binding_margin_mm * MM2PT

    def content_height_pt
      height_pt - top_margin_pt - bottom_margin_pt
    end

    def body_line_height
      content_height_pt / body_line_count
    end

    # The size's part of a design's name ("클래식 사륙판", "Classic 128x188"): its
    # Korean name in a Korean design, else an ASCII label, since a design's
    # language comes from its file name: the standard size's en_name, an ASCII
    # local_name, or "<W>x<H>".
    def self.name_label(locale, local_name:, width_mm:, height_mm:, en_name: nil)
      dims = "#{mm_label(width_mm)}x#{mm_label(height_mm)}"
      return local_name.presence || dims if locale.to_s == "ko"
      en_name ||= STANDARD_SIZES.find { |s| s[:local_name] == local_name }&.dig(:en_name)
      en_name.presence || (local_name if local_name.present? && local_name.ascii_only?) || dims
    end

    # 150.0 → "150", 220.5 → "220.5"
    def self.mm_label(mm) = mm.to_d.to_s("F").delete_suffix(".0")

    def name_label(locale) = self.class.name_label(locale, local_name:, width_mm:, height_mm:)

    def display_name
      local_name.present? ? "#{local_name} (#{width_mm.to_i}x#{height_mm.to_i}mm)" : size_name
    end

    # Text block size once margins are taken off, from the current (possibly
    # unsaved) values or, with stored: true, the saved ones. binding: whether
    # the binding margin comes off too — always for the 20 mm rule; for a
    # design's columns only where the layout binds them (DocumentDesign#columns_bind?).
    def text_width_mm(binding: true, stored: false)
      m = margin_reader(stored)
      m.("width_mm") - m.("left_margin_mm") - m.("right_margin_mm") - (binding ? m.("binding_margin_mm") : 0)
    end

    def text_width_pt(binding:, stored: false) = text_width_mm(binding: binding, stored: stored) * MM2PT
    def content_width_mm(stored: false) = text_width_mm(binding: true, stored: stored)

    def content_height_mm(stored: false)
      m = margin_reader(stored)
      m.("height_mm") - m.("top_margin_mm") - m.("bottom_margin_mm")
    end

    # Stored margins the Page section warns about (the paper size page never
    # checks these rules).
    def margin_problems
      [ (I18n.t("design.page_section.errors.too_narrow", min: MIN_CONTENT_MM) if content_width_mm < MIN_CONTENT_MM),
        (I18n.t("design.page_section.errors.too_short", min: MIN_CONTENT_MM) if content_height_mm < MIN_CONTENT_MM) ].compact
    end

    # Doc types on this size whose columns fit at the STORED margins but not
    # at the current (unsaved) ones — each at its own column width (binding
    # only where the layout binds its columns). A doc type already broken is
    # never listed, so a save is rejected only for what it newly breaks.
    def doc_types_newly_without_column_width
      document_designs.select do |dd|
        binding = dd.columns_bind?
        dd.columns_fit?(text_width_pt(binding: binding, stored: true)) && !dd.columns_fit?(text_width_pt(binding: binding))
      end.map(&:doc_type)
    end

    def generated_value(field) = Design::DefaultGenerator.new(self).generated_value(field)

    # The Page section's dot and ×: marked AND not what the rules generate (a
    # creation-time mark equal to the rule shows nothing).
    def margin_changed?(field)
      overridden?(field) && self[field].to_d != BigDecimal(generated_value(field).to_s)
    end

    private

    def theme_has_no_size
      return unless theme&.paper_sizes&.exists?
      errors.add(:theme, :one_size_only, message: I18n.t("design.paper_sizes.one_size_only"))
    end

    def page_section_margins
      fields = page_fields(PAGE_MARGIN_FIELDS)
      return if fields.empty?
      numbers = fields.index_with { |f| typed_number(f) }
      numbers.each { |f, n| page_error(f, :negative) if n&.negative? }
      return unless numbers.values.all? { |n| n && !n.negative? }

      if fields.intersect?(WIDTH_MARGIN_FIELDS)
        width_fields = fields & WIDTH_MARGIN_FIELDS
        if worse_under_min?(content_width_mm, content_width_mm(stored: true))
          width_fields.each { |f| page_error(f, :too_narrow, min: MIN_CONTENT_MM) }
        elsif (types = doc_types_newly_without_column_width).any?
          labels = types.map { |t| I18n.t("design.doc_types.#{t}", default: t) }.join(", ")
          width_fields.each { |f| page_error(f, :columns_elsewhere, doc_types: labels) }
        end
      end
      if fields.intersect?(HEIGHT_MARGIN_FIELDS) && worse_under_min?(content_height_mm, content_height_mm(stored: true))
        (fields & HEIGHT_MARGIN_FIELDS).each { |f| page_error(f, :too_short, min: MIN_CONTENT_MM) }
      end
    end

    # Under the minimum AND smaller than the stored size: a save that improves
    # a bad value is accepted even when it isn't a full fix.
    def worse_under_min?(now, stored) = now < MIN_CONTENT_MM && now < stored

    def margin_reader(stored) = ->(f) { (stored ? attribute_in_database(f) : self[f]).to_d }
  end
end
