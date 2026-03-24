Rails.application.routes.draw do
  root "events#index"

  resource :session, only: [ :new, :create, :destroy ]
  resource :nest_connection, only: [ :show, :new, :create, :destroy ] do
    get :callback, on: :member
  end

  resources :events, only: [ :index, :show ] do
    resource :retry, only: :create, module: :events
  end

  resources :cameras, only: [ :index, :show ] do
    resource :sync, only: :create, module: :cameras
    resource :stream, only: [ :show, :create, :update ], module: :cameras
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
