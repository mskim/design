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

    # One style exists once per language (and per owner, and per book): a Korean
    # and an English "Classic" sit side by side, and every book's design keeps its
    # starter's name. For system themes this validation is the only guard —
    # SQLite's unique index treats NULL user_ids / book_ids as distinct.
    validates :name, uniqueness: { scope: %i[user_id locale book_id] }

    # The style every new book defaults to.
    DEFAULT_STYLE = "classic"

    AVAILABLE_FONTS = [
      "smShinShinMyungjoP-30", "smShinShinMyungjo", "Shinmoon", # Korean gothic: Noto Sans KR (no smGothic)
      "NotoSerifKR-ExtraLight", "NotoSerifKR-Light", "NotoSerifKR-Regular", "NotoSerifKR-Medium",
      "NotoSerifKR-SemiBold", "NotoSerifKR-Bold", "NotoSerifKR-ExtraBold", "NotoSerifKR-Black",
      "NotoSansKR-Thin", "NotoSansKR-ExtraLight", "NotoSansKR-Light", "NotoSansKR-Regular",
      "NotoSansKR-Medium", "NotoSansKR-SemiBold", "NotoSansKR-Bold", "NotoSansKR-ExtraBold", "NotoSansKR-Black",
      "TimesNewRoman", "Georgia-Bold",
      "HiraMinProN-W3", "HiraMinProN-W6",
      "STSong", "STHeiti",
      "HakgyoansimGaeulsopungB", "HakgyoansimGaeulsopungL"
    ].freeze

    # Themes a book can start from (system and custom), i.e. everything but book designs.
    scope :starter_themes, -> { where(book_id: nil) }
    scope :system_themes, -> { starter_themes.where(user_id: nil) }
    scope :custom_themes, -> { starter_themes.where.not(user_id: nil) }

    # A book's own copy of a starter theme (the host's per-book design); never edited here.
    def book_design? = book_id.present?

    def system? = user_id.nil? && !book_design?

    # Where this theme's .db is exported: system themes at the root, custom themes
    # under their owner, book designs under their book.
    def export_dir
      base = Design.themes_dir
      return File.join(base, "book_#{book_id}") if book_design?
      system? ? base : File.join(base, "user_#{user_id}")
    end

    def db_path = File.join(export_dir, "#{file_basename}.db")

    def imported?
      imported_at.present?
    end

    # Single source of truth for "can this user edit this theme", shared by the
    # design UI (which chips/links to render) and the controllers' before_action.
    # Only designers edit themes ("users just use themes"). Custom themes are
    # shared across the one house's designers; system (baseline) themes are
    # always read-only — customize by cloning into a custom theme instead.
    # Book designs belong to the host's book and are never edited in the studio.
    def editable_by?(user)
      return false if book_design?
      system? ? Design.authoring? : Design.authorize(user)
    end

    def default_paper_size
      paper_sizes.order(:id).first
    end

    # The theme's file name without extension, used for every .db and
    # .book_design file: the style plus the language ("classic-ko"). A name that
    # parameterizes to nothing (all Korean, say) falls back to the id.
    def file_basename
      "#{name.to_s.parameterize.presence || "theme-#{id}"}-#{locale}"
    end

    # The default theme: the system Classic in `locale`, else the Korean one.
    # Books have no language yet, so callers pass nothing and get Korean.
    def self.default_for(locale = "ko")
      classic_in(locale) || classic_in("ko")
    end

    def self.classic_in(locale)
      system_themes.where(locale: locale.to_s).order(:id).detect { |t| t.name.to_s.parameterize == DEFAULT_STYLE }
    end
    private_class_method :classic_in

    private

    def seed_default_styles
      Design::ThemeStyleSeeder.call(self)
    end
  end
end
