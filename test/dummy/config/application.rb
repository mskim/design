require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

require "design"

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f

    config.action_controller.include_all_helpers = false

    config.autoload_lib(ignore: %w[assets tasks])

    # Load the engine's migrations alongside the dummy app's, if any exist.
    config.paths["db/migrate"] << File.expand_path("../../../db/migrate", __dir__)
  end
end
