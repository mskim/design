module RubyUI; end

require_relative "design/engine"

module Design
  class Configuration
    attr_accessor :current_user, :authorize, :authenticate, :user_class, :authoring,
                  :home_url, :locale_for, :themes_dir

    def initialize
      @user_class = "User"
      @authoring  = false
    end
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
