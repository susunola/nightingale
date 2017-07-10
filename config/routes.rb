Rails.application.routes.draw do
  # User related routes
  devise_for :users, :controllers => {registrations: 'registrations', passwords: 'passwords'}

  # Guest user related routes
  resources :guest_users, only: [:show], param: :guest_user_token, controller: 'guest_users'

  # Death Record related routes
  resources :death_records, only: [:index, :show, :new, :edit, :update] do
    member do
      post :update_step
      post :update_active_step
      post :users_by_role
      post :register
      post :request_edits
      post :abandon
      post :views_validate
    end
  end

  # Step related routes
  resources :step, only: [:update]

  # Comment related routes
  resources :comments, only: [:create, :destroy]

  # Geography related routes
  match 'geography_full' => 'geography#geography_full', :via => :post
  match 'geography_short' => 'geography#geography_short', :via => :post

  # Admin related routes
  resources :admins, only: [:index]
  resources :reports
  resources :statistics
  resources :questions
  resources :users

  # Statistics related routes
  resources :statistics do
    collection do
      post 'line_death_records_created'
      post 'line_death_records_completed'
      post 'line_users_created'
      post 'line_user_sign_ins'
      post 'pie_death_records_by_step'
      post 'bar_death_record_time_by_step'
      post 'bar_average_completion'
      post 'pie_death_record_ages_by_range'
    end
  end

  # Default route
  authenticated :user do
    root :to => 'death_records#index', :as => :authenticated_root
  end
  root :to => redirect('/users/sign_in')

  namespace :api, defaults: { format: :json } do
    namespace :v1 do
      resources :death_records
    end
  end
end
