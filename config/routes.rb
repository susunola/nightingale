Rails.application.routes.draw do
  resources :causes_of_deaths
  resources :cause_of_deaths
  resources :death_records do
    resources :steps, only: [:show, :update], controller: 'death_record/steps'
  end

  use_doorkeeper

  devise_for :users, :controllers => { :registrations => "registrations", :passwords => "passwords"}

  resources :guest_users, param: :guest_user_token, controller: 'guest_users'

  authenticated :user do
    root :to => 'death_records#index', :as => :authenticated_root
  end
  root :to => redirect('/users/sign_in')
end
