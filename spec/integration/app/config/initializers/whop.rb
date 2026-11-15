# frozen_string_literal: true

Rails.application.config.action_controller.allow_forgery_protection = true
Rails.application.config.hosts.clear

Devise.setup do |config|
  config.secret_key = "integration-test-secret"
  config.parent_controller = "ApplicationController"
  require "devise/orm/active_record"
  config.omniauth :whop, "app_integration", "integration-secret", sandbox: true if ENV["WHOP_INTEGRATION_MODE"] == "devise"
end

unless ENV["WHOP_INTEGRATION_MODE"] == "devise"
  Rails.application.config.middleware.use OmniAuth::Builder do
    provider :whop, "app_integration", "integration-secret", sandbox: true
  end
end
