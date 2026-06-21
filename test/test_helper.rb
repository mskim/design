# Configure Rails environment for the design engine's standalone test suite.
ENV["RAILS_ENV"] = "test"

require_relative "dummy/config/environment"

ActiveRecord::Migrator.migrations_paths = [ File.expand_path("dummy/db/migrate", __dir__) ]

# Build the schema into the (scratch) test DB. The dummy app has no migrations;
# its schema lives in test/dummy/db/schema.rb.
ActiveRecord::Schema.verbose = false
load File.expand_path("dummy/db/schema.rb", __dir__)

require "rails/test_help"

module ActiveSupport
  class TestCase
    # Engine fixtures (users.yml) live under test/fixtures.
    self.fixture_paths = [ File.expand_path("fixtures", __dir__) ]
    self.file_fixture_path = File.expand_path("fixtures/files", __dir__)
    fixtures :all

    # The suite runs in parallel and several tests flip Design.config
    # (authorize / authoring / authenticate). Snapshot + restore the whole
    # config around every test so mutations never leak across tests or workers.
    # CurrentDesigner (the signed-in user) is reset by Rails' CurrentAttributes
    # per-request/test, but we clear it defensively too.
    setup do
      @__design_config_snapshot = Design.config.dup
    end

    teardown do
      Design.instance_variable_set(:@config, @__design_config_snapshot)
      CurrentDesigner.reset
    end

    private

    # Sign in for the standalone engine: make Design.current_user resolve to the
    # given user WITHOUT any host session endpoint. Accepts a fixture name
    # (Symbol/String, e.g. :david) or a User record.
    #
    # Replaces the host's `sign_in :david`. The dummy app's authenticate proc
    # reads CurrentDesigner.user, so this also satisfies authenticate!.
    def sign_in(user)
      user = users(user) if user.is_a?(Symbol) || user.is_a?(String)
      CurrentDesigner.user = user
      user
    end

    # Explicit alias for the engine's vocabulary: sign in as someone who can
    # design. Defaults to the administrator fixture.
    def sign_in_designer(user = :david)
      sign_in(user)
    end

    def sign_out
      CurrentDesigner.user = nil
    end
  end
end
