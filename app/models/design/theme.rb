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

    # Write `attrs` (a permitted paragraph-style params hash) as a document-level
    # override of `name` onto every DocumentDesign of `doc_type` across this theme's
    # paper sizes (the current document is one of them). The theme base is untouched;
    # because all sizes share one base, identical override attrs resolve identically.
    def apply_paragraph_style_to_doc_type!(doc_type, name, attrs)
      document_designs.where(doc_type: doc_type).find_each do |dd|
        dd.upsert_paragraph_style!(name, attrs)
      end
    end

    # Write `attrs` to the theme base style `name` (creating the base row if a style
    # of that name exists only as a document override), then destroy every same-name
    # per-doc_type override across the theme so the base value shows everywhere.
    def apply_paragraph_style_to_all!(name, attrs)
      base = base_paragraph_styles.find_or_initialize_by(name: name)
      base.update!(attrs.except(:name))
      document_designs.find_each do |dd|
        dd.paragraph_styles.where(name: name).destroy_all
      end
      base
    end

    # Distinct doc_types that currently have a same-name document override — i.e. the
    # doc_types an "apply to all" save would reset. `.size` is the warning count.
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
