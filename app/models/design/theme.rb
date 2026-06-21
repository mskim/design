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

    private

    def seed_default_styles
      Design::ThemeStyleSeeder.call(self)
    end
  end
end
