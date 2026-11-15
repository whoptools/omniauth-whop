# frozen_string_literal: true

class SessionsController < ApplicationController
  def new
    path = ENV["WHOP_INTEGRATION_MODE"] == "devise" ? user_whop_omniauth_authorize_path : "/auth/whop"
    render html: helpers.button_to("Sign in with Whop", path, data: { turbo: false })
  end

  def create
    auth = request.env.fetch("omniauth.auth")
    user = User.find_or_create_by!(provider: auth.provider, uid: auth.uid)
    reset_session
    session[:user_id] = user.id
    redirect_to "/me"
  end

  def show
    user = ENV["WHOP_INTEGRATION_MODE"] == "devise" ? current_user : User.find_by(id: session[:user_id])
    user ? render(json: { uid: user.uid }) : head(:unauthorized)
  end

  def failure
    head :unauthorized
  end
end
