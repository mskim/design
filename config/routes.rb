Design::Engine.routes.draw do
  resources :themes, only: [:index, :show, :new, :create, :edit, :update, :destroy] do
    post :clone, on: :member
    post :generate_sizes, on: :member
    resources :theme_paragraph_styles, only: [:edit, :update], controller: "theme_paragraph_styles"
    resources :paper_sizes, only: [:new, :create, :edit, :update, :destroy] do
      post :regenerate, on: :member
      resources :base_paragraph_styles, only: [:edit, :update], controller: "base_paragraph_styles"
      resources :document_designs, only: [:edit, :update] do
        member do
          get :preview
          post :preview
          get :preview_jpg
          get :properties_panel
          get :panel
          patch :panel_update
        end
        # paragraph_styles edit/update stay on ParagraphStylesController (its own scoped
        # set_paragraph_style); the override/revert/new/create flow lives on
        # DocumentDesignsController (alongside panel/panel_update) — hence two blocks.
        resources :paragraph_styles, only: [:edit, :update]
        resources :paragraph_styles, only: [:new, :create], controller: "document_designs" do
          collection do
            post :override
          end
          member do
            delete :revert
          end
        end
      end
    end
  end
end
