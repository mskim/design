module Design
  class Theme < Design::ApplicationRecord
    self.table_name = "design_themes"

    # user_class is read once at class-load time (the initializer must run first,
    # which it does — config/initializers run before models autoload). A host
    # cannot reconfigure the association class at runtime.
    belongs_to :user, class_name: Design.config.user_class, optional: true
    has_many :paper_sizes, class_name: "Design::PaperSize", dependent: :destroy
    has_many :document_designs, through: :paper_sizes
    has_many :base_paragraph_styles, as: :styleable, class_name: "Design::ParagraphStyle", dependent: :destroy
    has_many :table_styles, class_name: "Design::TableStyle", dependent: :destroy

    after_create :seed_default_styles

    validates :name, presence: true
    validates :locale, presence: true, inclusion: { in: %w[ko en ja zh] }

    AVAILABLE_FONTS = [
      "smShinShinMyungjoP-30", "smShinShinMyungjo", "smGothicP-10", "smGothicP-30", "Shinmoon",
      "NotoSerifKR-ExtraLight", "NotoSerifKR-Light", "NotoSerifKR-Regular", "NotoSerifKR-Medium",
      "NotoSerifKR-SemiBold", "NotoSerifKR-Bold", "NotoSerifKR-ExtraBold", "NotoSerifKR-Black",
      "NotoSansKR-Thin", "NotoSansKR-ExtraLight", "NotoSansKR-Light", "NotoSansKR-Regular",
      "NotoSansKR-Medium", "NotoSansKR-SemiBold", "NotoSansKR-Bold", "NotoSansKR-ExtraBold", "NotoSansKR-Black",
      "TimesNewRoman", "Georgia-Bold",
      "HiraMinProN-W3", "HiraMinProN-W6",
      "STSong", "STHeiti",
      "HakgyoansimGaeulsopungB", "HakgyoansimGaeulsopungL"
    ].freeze

    scope :system_themes, -> { where(user_id: nil) }
    scope :custom_themes, -> { where.not(user_id: nil) }

    def system?
      user_id.nil?
    end

    def imported?
      imported_at.present?
    end

    # Single source of truth for "can this user edit this theme", shared by the
    # design UI (which chips/links to render) and the controllers' before_action.
    # Only designers edit themes ("users just use themes"). Custom themes are
    # shared across the one house's designers; system (baseline) themes are
    # always read-only — customize by cloning into a custom theme instead.
    def editable_by?(user)
      system? ? Design.authoring? : Design.authorize(user)
    end

    def default_paper_size
      paper_sizes.order(:id).first
    end

    # "Apply to all": write `attrs` (only the fields the user changed) to the
    # theme base style `name` — creating the base row if the style exists only as
    # doc-type rows — then clear the `clear` style fields (default: attrs' keys)
    # on every same-name doc-type row across the theme, so the base value shows
    # everywhere. Other fields' overrides are kept; rows left empty are deleted
    # (they now have a parent).
    def apply_paragraph_style_to_all!(name, attrs, clear: attrs.keys)
      attrs = attrs.to_h.stringify_keys.except("name")
      fields = clear.map(&:to_s) & Design::ParagraphStyle::STYLE_FIELDS
      transaction do
        base = base_paragraph_styles.find_or_initialize_by(name: name)
        base.update!(attrs)
        document_designs.find_each { |dd| dd.clear_style_fields!(name, fields) } if fields.any?
        # Deleting rows doesn't bump the preview-cache fingerprint; touch instead.
        document_designs.update_all(updated_at: Time.current)
        base
      end
    end

    # Distinct doc_types that currently have a same-name document override — i.e. the
    # doc_types whose overrides an "apply to all" save may clear. `.size` is the
    # warning count.
    def shadow_override_doc_types(name)
      document_designs
        .joins(:paragraph_styles)
        .where(design_paragraph_styles: { name: name })
        .distinct
        .pluck(:doc_type)
    end

    private

    def seed_default_styles
      Design::ThemeStyleSeeder.call(self)
    end
  end
end
