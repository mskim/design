module Design
  class ApplicationController < ActionController::Base
    layout "design"

    protect_from_forgery with: :exception

    before_action :authenticate!
    before_action :authorize_designer!

    around_action :switch_design_locale

    private

    # -------------------------------------------------------------------------
    # Authentication
    # Runs the host-provided authenticate proc in controller context so it has
    # full access to cookies, session, redirect_to, etc.  The proc is expected
    # to set Current.user (via Current.session) or halt the request.
    # -------------------------------------------------------------------------
    def authenticate!
      if (proc = Design.config.authenticate)
        instance_exec(&proc)
      end
      # If no authenticate proc is configured (e.g. standalone/test mode),
      # fall through — authorize_designer! denies the resulting nil user.
    end

    # -------------------------------------------------------------------------
    # Authorization
    # Uses Design.authorize(user) so the engine is independent of the host's
    # Authorization concern. A nil current user is always denied here (before
    # the host's authorize proc runs), so the proc never needs to be nil-safe.
    # -------------------------------------------------------------------------
    def authorize_designer!
      user = Design.current_user
      head :forbidden unless user && Design.authorize(user)
    end

    # -------------------------------------------------------------------------
    # Locale
    # Mirrors the host app's switch_locale semantics: reads host-provided
    # locale_for proc (e.g. session[:locale]) then falls back to default_locale.
    # -------------------------------------------------------------------------
    def switch_design_locale(&action)
      locale = begin
        Design.config.locale_for ? instance_exec(&Design.config.locale_for) : nil
      rescue => e
        Rails.logger.warn("[Design] locale_for proc raised #{e.class}: #{e.message}; using default locale")
        nil
      end
      I18n.with_locale(locale || I18n.default_locale, &action)
    end

    # -------------------------------------------------------------------------
    # Theme helpers (used by child controllers)
    # -------------------------------------------------------------------------
    def set_theme
      @theme = accessible_themes.find(params[:theme_id] || params[:id])
    end

    def ensure_theme_editable
      head :forbidden unless @theme.editable_by?(Design.current_user)
    end

    # Every theme (system baselines + all house custom themes) is reachable
    # in the studio; per-theme edit rights are enforced by ensure_theme_editable.
    def accessible_themes
      Design::Theme.all
    end
  end
end
