# frozen_string_literal: true

require "sidekiq/web"
require "sidekiq-scheduler/web"

Rails.application.routes.draw do
  match "(*any)", to: redirect(subdomain: ""), via: :all, constraints: {subdomain: "www"}
  match "(*any)", to: redirect { |_, req| "https://visualizer.coffee#{req.fullpath}" }, via: :all, constraints: {host: "decent-visualizer.herokuapp.com"}

  authenticate :user, ->(user) { user.admin? } do
    mount Sidekiq::Web => "/sidekiq"
    mount PgHero::Engine => "pghero"
  end

  devise_for :users
  use_doorkeeper do
    controllers applications: "oauth/applications"
  end

  root to: "home#show"

  namespace :api do
    get :me, to: "credentials#me"
    resources :shots, only: %i[index destroy] do
      get :download
      get :profile
      collection do
        get :shared
        post :upload
      end
    end
  end

  get :changelog, to: "changes#index"
  get :privacy, to: "home#privacy"
  post :stripe, to: "stripe#create"

  resources :people, only: %i[index show] do
    post :search, on: :collection
    get :search, on: :collection
    get :feed, on: :member
  end

  resources :shots, except: [:new] do
    member do
      delete :remove_image
      get :share
      get "/compare/:comparison", to: "shots#compare"
    end
    collection do
      get :enjoyments
      get :recents
    end
  end

  resources :search, only: [:index] do
    collection do
      get :autocomplete
    end
  end

  resources :profiles, only: %i[edit update] do
    get :reset_chart_settings
    get :edit, on: :collection
  end

  resources :premium, only: %i[index create] do
    post :update
    collection do
      get :success
      get :cancel
    end
  end

  resources :stats, only: [:index]
  resources :changes, except: %i[index destroy]

  match "/404", to: "errors#not_found", via: :all
  match "/500", to: "errors#internal_server_error", via: :all
end
