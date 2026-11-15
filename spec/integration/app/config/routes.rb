# frozen_string_literal: true

Rails.application.routes.draw do
  root "sessions#new"
  get "/me", to: "sessions#show"
  if ENV["WHOP_INTEGRATION_MODE"] == "devise"
    devise_for :users, controllers: { omniauth_callbacks: "callbacks" }
  else
    get "/auth/whop/callback", to: "sessions#create"
  end
  get "/auth/failure", to: "sessions#failure"
end
