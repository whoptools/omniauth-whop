# frozen_string_literal: true

class User < ApplicationRecord
  devise :database_authenticatable, :omniauthable, omniauth_providers: [:whop] if ENV["WHOP_INTEGRATION_MODE"] == "devise"
end
