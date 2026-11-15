# frozen_string_literal: true

class CallbacksController < Devise::OmniauthCallbacksController
  def whop
    auth = request.env.fetch("omniauth.auth")
    user = User.find_or_create_by!(provider: auth.provider, uid: auth.uid)
    sign_in(user)
    redirect_to "/me"
  end

  def failure
    head :unauthorized
  end
end
