require "test_helper"

# Tests for Design::ApplicationController's standalone auth/authz before-actions.
# These are independent of any host Authorization concern — they verify that
# the engine's own authenticate! / authorize_designer! work through config.
class Design::ApplicationControllerAuthTest < ActionDispatch::IntegrationTest
  setup do
    @saved_config = Design.config.dup
  end

  teardown do
    Design.instance_variable_set(:@config, @saved_config)
  end

  # -------------------------------------------------------------------------
  # authorize_designer! — 403 when Design.authorize returns false
  # -------------------------------------------------------------------------

  test "authorize_designer! returns 403 when user cannot design" do
    # Sign in as kevin who is NOT a designer by default
    sign_in :kevin
    get "/design/themes"
    assert_response :forbidden
  end

  test "authorize_designer! proceeds when user can design (admin)" do
    sign_in :david  # admin → can_design? == true
    get "/design/themes"
    assert_response :success
  end

  test "authorize_designer! proceeds when user has designer role" do
    users(:kevin).update!(role: :designer)
    sign_in :kevin
    get "/design/themes"
    assert_response :success
  end

  # -------------------------------------------------------------------------
  # authenticate! — unauthenticated access redirects
  # -------------------------------------------------------------------------

  test "unauthenticated request to design studio redirects to sign in" do
    get "/design/themes"
    assert_response :redirect
    assert_redirected_to "/session/new"
  end

  # -------------------------------------------------------------------------
  # Design.authorize config independence
  # -------------------------------------------------------------------------

  test "authorize_designer! uses Design.authorize config, not host Authorization concern" do
    # Override authorize to allow all authenticated users (even non-designers)
    Design.configure { |c| c.authorize = ->(_user) { true } }

    sign_in :kevin  # kevin is not a designer, but config allows everyone
    get "/design/themes"
    assert_response :success
  end

  test "authorize_designer! can be configured to deny everyone" do
    Design.configure { |c| c.authorize = ->(_user) { false } }

    sign_in :david  # david is admin, but config denies everyone
    get "/design/themes"
    assert_response :forbidden
  end

  # -------------------------------------------------------------------------
  # Standalone mode — no authenticate proc resolves a nil user
  # -------------------------------------------------------------------------

  test "no authenticate proc → nil user is denied (403) without raising, even when authorize is not nil-safe" do
    # Simulate a host (or gem standalone mode) that wires authorize but forgets
    # authenticate. The nil current user must be denied BEFORE the authorize
    # proc runs, so a non-nil-safe proc never blows up.
    Design.configure do |c|
      c.authenticate = nil
      c.authorize    = ->(user) { user.can_design? } # deliberately NOT nil-safe
    end

    get "/design/themes"
    assert_response :forbidden
  end
end
