# Thread-local holder for the "signed-in" user in the dummy test app.
#
# The design engine is host-agnostic: it resolves the current user through
# `Design.config.current_user` and authenticates through
# `Design.config.authenticate`. This dummy wires both (config/initializers/design.rb)
# to read from here, and the test helper's `sign_in` / `sign_out` set it.
#
# NOTE: this is a plain thread/fiber-local, NOT an ActiveSupport::CurrentAttributes.
# Integration tests reset CurrentAttributes around every dispatched request, which
# would clear a user set in `setup` before the controller's authenticate! runs.
# A bare thread-local survives the request boundary, mirroring how a real host
# session would. Per-fiber storage keeps parallel test workers isolated.
module CurrentDesigner
  KEY = :__design_dummy_current_user

  class << self
    def user
      Thread.current[KEY]
    end

    def user=(value)
      Thread.current[KEY] = value
    end

    def reset
      Thread.current[KEY] = nil
    end
  end
end
