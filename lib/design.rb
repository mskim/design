module RubyUI; end

require_relative "design/engine"
require_relative "design/action_registry"

module Design
  class Configuration
    attr_accessor :current_user, :authorize, :authenticate, :user_class, :authoring,
                  :home_url, :locale_for, :themes_dir, :table_style_preview,
                  # A lambda evaluated in the view context returning an image URL,
                  # like home_url — nil falls back to the built-in house icon.
                  :home_icon,
                  # true, or a lambda returning it: lay previews out with DesignCraft (designcraft_rb
                  # and designcraft-cli, the host's), as the host prints books. Design::PreviewService.
                  :designcraft
    attr_writer :sample_content_dir

    def initialize
      @user_class = "User"
      @authoring  = false
    end

    # Host directory holding editable sample text (<locale>/<doc_type>.md). The gem's
    # bundled db/sample_content is the read-only fallback (see Design::SampleContent).
    def sample_content_dir
      @sample_content_dir || Rails.root.join("db/sample_content").to_s
    end

    def actions = @actions ||= Design::ActionRegistry.new
  end

  class << self
    def configure
      yield config
    end

    def config
      @config ||= Configuration.new
    end

    def authoring?
      !!config.authoring
    end

    def current_user
      config.current_user&.call
    end

    def authorize(user)
      !!config.authorize&.call(user)
    end

    def home_url
      config.home_url
    end

    def locale_for
      config.locale_for
    end

    def designcraft?
      value = config.designcraft
      !!(value.respond_to?(:call) ? value.call : value)
    end

    # Back-compat: keep Design.themes_dir / Design.themes_dir= working.
    # The engine initializer calls `Design.themes_dir ||= ENV.fetch(...)`
    # which expands to `Design.themes_dir = ... unless Design.themes_dir`.
    # Routing through config keeps everything consistent.
    def themes_dir
      config.themes_dir
    end

    def themes_dir=(value)
      config.themes_dir = value
    end
  end
end
