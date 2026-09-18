Design::Engine.routes.draw do
  resources :themes, only: [:index, :show, :new, :create, :edit, :update, :destroy] do
    post :clone, on: :member
    post :generate_sizes, on: :member
    resources :theme_paragraph_styles, only: [:edit, :update], controller: "theme_paragraph_styles"
    resources :sample_contents, only: [ :edit, :update ], param: :doc_type do
      post :restore, on: :member
    end
    resources :table_styles, only: [ :show, :edit, :update ] do
      member do
        get :preview, to: "table_style_previews#show", as: :preview
        post :reset
      end
    end
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
        # Doc-type styles are edited through panel/panel_update (field-level, every
        # paper size); the override/revert/new/create flow lives alongside them.
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
