Rails.application.routes.draw do
  mount Design::Engine => "/design"

  # Stand-in for the host's sign-in page. The dummy's `authenticate` proc
  # redirects unauthenticated requests here (mirrors book_write's /session/new).
  get "/session/new", to: "host_pages#new_session", as: :new_session

  # Stand-in for the host's home page (books#index in book_write). The JS
  # isolation test GETs root_path and asserts host pages do NOT load the
  # engine's JS module.
  root to: "host_pages#home"
end
