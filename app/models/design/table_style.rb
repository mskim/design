module Design
  class TableStyle < Design::ApplicationRecord
    self.table_name = "design_table_styles"

    belongs_to :theme, class_name: "Design::Theme"

    ALLOWED_NAMES = %w[grid zebra striped minimal simple].freeze
    BORDER_STYLES = %w[full horizontal none outer_only].freeze
    FONT_WEIGHTS  = %w[normal bold].freeze

    # A host may give the table a nullable doc_type (book_write: a document type's
    # own tables). Rows without one are the defaults; without the column (book_design)
    # every row is. Asked each time, so a column added at runtime is seen.
    def self.typed? = column_names.include?("doc_type")

    scope :defaults, -> { typed? ? where(doc_type: nil) : all }
    scope :for_type, ->(doc_type) { where(doc_type: doc_type) }

    validates :name, presence: true, inclusion: { in: ALLOWED_NAMES }
    validate :name_unique_in_scope
    validates :border_style, inclusion: { in: BORDER_STYLES }, allow_nil: true
    validates :header_font_weight, inclusion: { in: FONT_WEIGHTS }, allow_nil: true

    private

    # Unique per theme, and per document type when the table has the column.
    def name_unique_in_scope
      return if name.blank?
      others = self.class.where(theme_id: theme_id, name: name)
      others = others.where(doc_type: doc_type) if self.class.typed?
      others = others.where.not(id: id) if persisted?
      errors.add(:name, :taken) if others.exists?
    end
  end
end
