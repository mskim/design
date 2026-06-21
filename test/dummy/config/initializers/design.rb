# Wire the host-agnostic design engine to the dummy app, mirroring how
# book_write configures it — but driven by the test harness's CurrentDesigner
# instead of a real session store.
#
# Tests flip `authorize` / `authoring` per-case; test_helper captures and
# restores Design.config around every test so those mutations don't leak across
# parallel workers.
Design.configure do |config|
  config.user_class = "User"
  config.authoring  = false

  # Resolve the signed-in user from the thread-local set by the test helper's
  # sign_in. Design.current_user calls this proc.
  config.current_user = -> { CurrentDesigner.user }

  # Only designers edit themes; everyone else is a "user" of themes.
  config.authorize = ->(user) { user&.can_design? }

  # Runs in controller context (instance_exec). Mirrors book_write's
  # require_authentication: bounce unauthenticated requests to the sign-in page.
  config.authenticate = -> { redirect_to "/session/new" unless CurrentDesigner.user }

  # "Back to home" link target. Evaluated in view/controller context
  # (helpers.instance_exec), mirroring book_write's `-> { main_app.root_path }`.
  config.home_url = -> { main_app.root_path }

  # Standalone studio uses the default locale; no host session locale.
  config.locale_for = nil

  # Render previews against per-theme .db files written under a scratch dir.
  config.themes_dir = Rails.root.join("tmp/themes").to_s
end
