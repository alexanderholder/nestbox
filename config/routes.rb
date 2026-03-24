Rails.application.routes.draw do
  root "events#index"

  resource :session, only: [ :new, :create, :destroy ]
  resource :nest_connection, only: [ :show, :new, :create, :destroy ] do
    get :callback, on: :member
  end

  resources :cameras, only: [ :index, :show ] do
    resource :sync, only: :create, module: :cameras
    resource :stream, only: [ :show, :create, :update ], module: :cameras
  end

  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
