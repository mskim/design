# Stand-ins for host pages the engine tests reach for:
#   * home          — the host's books#index (a non-engine page). The JS
#                     isolation test asserts it does NOT load the engine JS module.
#   * new_session   — the host's sign-in page the engine redirects unauthenticated
#                     requests to.
class HostPagesController < ApplicationController
  def home
    render html: "host home page".html_safe
  end

  def new_session
    render html: "sign in".html_safe
  end
end
