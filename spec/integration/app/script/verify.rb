# frozen_string_literal: true

require_relative "../config/environment"
require "rack/test"
require "webmock"
require "nokogiri"

WebMock.enable!
WebMock.disable_net_connect!
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.define do
  create_table :users do |t|
    t.string :email, default: ""
    t.string :encrypted_password, default: ""
    t.string :provider, null: false
    t.string :uid, null: false
  end
  add_index :users, %i[provider uid], unique: true
end

class LoginVerification
  include Rack::Test::Methods
  include WebMock::API

  def app = Rails.application

  def check(condition, message)
    raise message unless condition

    puts "PASS #{ENV.fetch('WHOP_INTEGRATION_MODE')}: #{message}"
  end

  def login_form
    get "/"
    check(last_response.status == 200, "renders login form")
    form = Nokogiri::HTML(last_response.body).at_css("form")
    [form["action"], form.at_css('input[name="authenticity_token"]')["value"]]
  end

  def verify
    action, csrf = login_form
    post action, authenticity_token: csrf
    check(last_response.status == 302, "accepts Rails CSRF token")
    auth_url = URI(last_response.headers.fetch("location"))
    check(auth_url.host == "sandbox-api.whop.com", "redirects to sandbox provider")
    params = URI.decode_www_form(auth_url.query).to_h
    callback = URI(params.fetch("redirect_uri")).path
    expected_path = ENV["WHOP_INTEGRATION_MODE"] == "devise" ? "/users/auth/whop/callback" : "/auth/whop/callback"
    check(callback == expected_path, "uses the correct callback route")
    key = OpenSSL::PKey::EC.generate("prime256v1")
    jwk = JWT::JWK.new(key)
    claims = { iss: "https://api.whop.com", aud: "app_integration", sub: "user_integration",
               nonce: params.fetch("nonce"), iat: Time.now.to_i, exp: Time.now.to_i + 300 }
    id_token = JWT.encode(claims, key, "ES256", kid: jwk.kid)
    stub_request(:post, "https://sandbox-api.whop.com/oauth/token")
      .with(body: hash_including("code" => "test-code", "redirect_uri" => params.fetch("redirect_uri"),
                                 "client_id" => "app_integration", "client_secret" => "integration-secret"))
      .to_return(headers: { "Content-Type" => "application/json" },
                 body: JSON.generate(access_token: "secret-token", token_type: "Bearer", expires_in: 3600, id_token: id_token))
    stub_request(:get, "https://sandbox-api.whop.com/.well-known/jwks.json")
      .to_return(headers: { "Content-Type" => "application/json" }, body: JSON.generate(keys: [jwk.export]))
    stub_request(:get, "https://sandbox-api.whop.com/oauth/userinfo")
      .with(headers: { "Authorization" => "Bearer secret-token" })
      .to_return(headers: { "Content-Type" => "application/json" }, body: JSON.generate(sub: "user_integration"))
    get callback, code: "test-code", state: params.fetch("state")
    check(last_response.status == 302, "accepts a signed OAuth callback through the real middleware")
    follow_redirect!
    check(last_response.status == 200 && JSON.parse(last_response.body)["uid"] == "user_integration", "persists an authenticated session")
    check(!last_response.body.include?("secret-token"), "keeps access tokens out of the response")
    get callback, code: "test-code", state: params.fetch("state")
    follow_redirect! if last_response.redirect?
    check(last_response.status == 401, "rejects callback replay")
    clear_cookies
    action, = login_form
    post action
    follow_redirect! if last_response.redirect?
    check([401, 422].include?(last_response.status), "rejects initiation without CSRF")
    get "/me"
    check(last_response.status == 401, "does not authenticate a rejected request")
    check(User.count == 1, "creates only the validated identity")
  end
end

LoginVerification.new.verify
puts "Verified Rails #{Rails.version}, Devise #{Gem.loaded_specs.fetch('devise').version}, omniauth-whop #{OmniAuth::Whop::VERSION}"
