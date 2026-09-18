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
        end
        # A doc type's paragraph style, keyed by name (D2b): the panel, field
        # saves, revert and push. "new" is reserved (styles/new is the form).
        resources :styles, only: [ :show, :new, :create, :destroy ], param: :name,
                  controller: "document_design_styles", format: false, constraints: { name: %r{[^/]+} } do
          member do
            patch :field, action: :update_field
            delete :field, action: :revert_field, as: :revert_field
            post :push
          end
        end
        # The design editor's Page section (D3): one field per request. Margins
        # land on the paper size, body lines / columns / gutter on this design.
        resource :page, only: [], controller: "document_design_pages", format: false do
          patch :field, action: :update_field
          delete :field, action: :revert_field, as: :revert_field
        end
      end
    end
  end
end
