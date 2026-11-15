# frozen_string_literal: true

require "spec_helper"

RSpec.describe OmniAuth::Strategies::Whop do
  let(:session) { {} }
  let(:options) { {} }
  let(:client_id) { "app_example" }
  let(:client_secret) { "example-secret" }
  let(:key) { OpenSSL::PKey::EC.generate("prime256v1") }
  let(:jwk) { JWT::JWK.new(key) }
  let(:base_url) { options[:sandbox] ? "https://sandbox-api.whop.com" : "https://api.whop.com" }
  let(:profile) do
    { "sub" => "user_example", "name" => "Example User", "preferred_username" => "example",
      "email" => "example@example.com", "email_verified" => false, "picture" => "https://example.com/avatar.png" }
  end
  let(:app) do
    lambda do |env|
      @auth = env["omniauth.auth"]
      [200, { "content-type" => "text/plain" }, ["signed in"]]
    end
  end
  let(:strategy) { described_class.new(app, client_id, client_secret, options) }

  def env_for(path, method: "GET", params: {})
    Rack::MockRequest.env_for("http://example.org#{path}", method: method, params: params)
                     .merge("rack.session" => session)
  end

  def start_login
    csrf_token = Rack::Protection::AuthenticityToken.token(session)
    response = strategy.call(env_for("/auth/whop", method: "POST", params: { authenticity_token: csrf_token }))
    expect(response[0]).to eq(302)
    URI.decode_www_form(URI(response[1].fetch("location")).query).to_h
  end

  def claims(login)
    { "iss" => "https://api.whop.com", "sub" => "user_example", "aud" => client_id,
      "iat" => Time.now.to_i, "exp" => Time.now.to_i + 300, "nonce" => login.fetch("nonce") }
  end

  def stub_oauth(login, overrides: {}, signing_key: key, id_token: :signed)
    payload = claims(login).merge(overrides)
    token = id_token == :signed ? JWT.encode(payload, signing_key, "ES256", kid: jwk.kid) : id_token
    @token_request = stub_request(:post, "#{base_url}/oauth/token").to_return(
      headers: { "Content-Type" => "application/json" },
      body: JSON.generate(access_token: "access-token", token_type: "Bearer", expires_in: 3600,
                          refresh_token: "refresh-token", id_token: token)
    )
    stub_request(:get, "#{base_url}/.well-known/jwks.json").to_return(
      headers: { "Content-Type" => "application/json" }, body: JSON.generate(keys: [jwk.export])
    )
    @profile_request = stub_request(:get, "#{base_url}/oauth/userinfo")
                       .with(headers: { "Authorization" => "Bearer access-token" })
                       .to_return(headers: { "Content-Type" => "application/json" }, body: JSON.generate(profile))
  end

  def callback(login, params = {})
    strategy.call(env_for("/auth/whop/callback",
                          params: { code: "authorization-code", state: login["state"] }.merge(params)))
  end

  it "uses POST-only initiation and rejects a missing CSRF token" do
    expect(strategy.call(env_for("/auth/whop"))[0]).to eq(200)
    expect(strategy.call(env_for("/auth/whop", method: "POST"))[0]).to eq(401)
    expect(WebMock).not_to have_requested(:any, /whop.com/)
  end

  it "requests identity scopes, a fresh state and nonce, and S256 PKCE" do
    login = start_login
    expect(login).to include("scope" => "openid profile email", "code_challenge_method" => "S256",
                             "redirect_uri" => "http://example.org/auth/whop/callback")
    verifier = session.fetch("omniauth.pkce.verifier")
    expect(login["code_challenge"]).to eq(Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false))
    second_login = start_login
    %w[state nonce code_challenge].each { |field| expect(second_login[field]).not_to eq(login[field]) }
  end

  it "bounds the nonce session storage" do
    5.times { start_login }
    expect(session.fetch("omniauth.whop.nonces").size).to eq(3)
  end

  it "authenticates and maps the standard auth hash, preserving false email verification" do
    login = start_login
    verifier = session.fetch("omniauth.pkce.verifier")
    stub_oauth(login)
    expect(callback(login)[0]).to eq(200)
    expect(@auth).to include("provider" => "whop", "uid" => "user_example")
    expect(@auth.info.to_h).to eq("name" => "Example User", "nickname" => "example",
                                  "email" => "example@example.com", "email_verified" => false,
                                  "image" => "https://example.com/avatar.png")
    expect(@auth.credentials).to include("token" => "access-token", "refresh_token" => "refresh-token",
                                         "expires" => true)
    expect(@auth.extra.raw_info.to_h).to eq(profile)
    expect(@token_request.with(body: hash_including("client_id" => client_id, "client_secret" => client_secret,
                                                    "code_verifier" => verifier,
                                                    "redirect_uri" => "http://example.org/auth/whop/callback"))).to have_been_requested.once
    expect(@profile_request).to have_been_requested.once
    expect(session.fetch("omniauth.whop.nonces")).to be_empty
  end

  it "allows overlapping sign-ins to finish in either order" do
    first = start_login
    first_verifier = session.fetch("omniauth.pkce.verifier")
    second = start_login
    stub_oauth(first)
    expect(callback(first)[0]).to eq(200)
    expect(@token_request.with(body: hash_including("code_verifier" => first_verifier))).to have_been_requested.once
    stub_oauth(second)
    expect(callback(second)[0]).to eq(200)
  end

  it "rejects a replayed callback" do
    login = start_login
    stub_oauth(login)
    expect(callback(login)[0]).to eq(200)
    expect(callback(login)[0]).to eq(401)
    expect(@token_request).to have_been_requested.once
  end

  [nil, "wrong-state"].each do |state|
    it "rejects #{state.inspect} state before exchanging tokens" do
      login = start_login
      expect(callback(login, state: state)[0]).to eq(401)
      expect(WebMock).not_to have_requested(:any, /whop.com/)
    end
  end

  it "handles denied consent" do
    login = start_login
    expect(callback(login, error: "access_denied")[2]).to eq(["access_denied"])
    expect(WebMock).not_to have_requested(:any, /whop.com/)
    expect(session.fetch("omniauth.whop.nonces")).to be_empty
  end

  {
    "nonce" => "wrong", "iss" => "https://attacker.example", "aud" => "another-app",
    "exp" => 1, "iat" => 4_000_000_000, "sub" => "", "azp" => "another-app"
  }.each do |field, value|
    it "rejects an invalid #{field} claim" do
      login = start_login
      stub_oauth(login, overrides: { field => value })
      expect(callback(login)[0]).to eq(401)
      expect(@profile_request).not_to have_been_requested
    end
  end

  it "rejects an ID token signed by another key" do
    login = start_login
    stub_oauth(login, signing_key: OpenSSL::PKey::EC.generate("prime256v1"))
    expect(callback(login)[0]).to eq(401)
  end

  [nil, "not-a-jwt"].each do |id_token|
    it "rejects #{id_token.inspect} ID tokens" do
      login = start_login
      stub_oauth(login, id_token: id_token)
      expect(callback(login)[0]).to eq(401)
    end
  end

  it "rejects a missing required expiry claim" do
    login = start_login
    token = JWT.encode(claims(login).except("exp"), key, "ES256", kid: jwk.kid)
    stub_oauth(login, id_token: token)
    expect(callback(login)[0]).to eq(401)
  end

  it "rejects multiple audiences without the expected authorized party" do
    login = start_login
    stub_oauth(login, overrides: { "aud" => [client_id, "another-app"] })
    expect(callback(login)[0]).to eq(401)
  end

  it "rejects a mismatched userinfo subject" do
    login = start_login
    profile["sub"] = "different-user"
    stub_oauth(login)
    expect(callback(login)[0]).to eq(401)
  end

  it "supports absent optional profile fields" do
    login = start_login
    profile.replace("sub" => "user_example")
    stub_oauth(login)
    expect(callback(login)[0]).to eq(200)
    expect(@auth.info.to_h).to eq({})
  end

  it "handles a token endpoint error" do
    login = start_login
    stub_request(:post, "#{base_url}/oauth/token").to_return(status: 401, body: '{"error":"invalid_grant"}',
                                                             headers: { "Content-Type" => "application/json" })
    expect(callback(login)[0]).to eq(401)
  end

  it "handles a timeout" do
    login = start_login
    stub_request(:post, "#{base_url}/oauth/token").to_timeout
    expect(callback(login)[0]).to eq(401)
  end

  context "in sandbox" do
    let(:options) { { sandbox: true } }

    it "uses sandbox endpoints for the whole flow" do
      expect(strategy.client.site).to eq(base_url)
      login = start_login
      stub_oauth(login)
      expect(callback(login)[0]).to eq(200)
      expect(WebMock).not_to have_requested(:any, %r{https://api.whop.com/})
    end
  end

  context "with custom scopes" do
    let(:options) { { scope: "profile" } }

    it "retains the required openid scope" do
      expect(start_login["scope"]).to eq("openid profile")
    end
  end
  it "accepts a rotated signing key on the next login" do
    first = start_login
    stub_oauth(first)
    expect(callback(first)[0]).to eq(200)
    second = start_login
    replacement = OpenSSL::PKey::EC.generate("prime256v1")
    replacement_jwk = JWT::JWK.new(replacement)
    token = JWT.encode(claims(second), replacement, "ES256", kid: replacement_jwk.kid)
    stub_oauth(second, id_token: token)
    stub_request(:get, "#{base_url}/.well-known/jwks.json").to_return(
      headers: { "Content-Type" => "application/json" }, body: JSON.generate(keys: [replacement_jwk.export])
    )
    expect(callback(second)[0]).to eq(200)
    expect(a_request(:get, "#{base_url}/.well-known/jwks.json")).to have_been_made.twice
  end

  it "rejects a signing key ID that the provider does not advertise" do
    login = start_login
    stub_oauth(login, id_token: JWT.encode(claims(login), key, "ES256", kid: "unknown-key"))
    expect(callback(login)[0]).to eq(401)
    expect(@profile_request).not_to have_been_requested
  end

  it "rejects an unsigned identity token" do
    login = start_login
    stub_oauth(login, id_token: JWT.encode(claims(login), nil, "none"))
    expect(callback(login)[0]).to eq(401)
    expect(@profile_request).not_to have_been_requested
  end

  it "rejects a callback after the session nonce is lost" do
    login = start_login
    session.delete("omniauth.whop.nonces")
    stub_oauth(login)
    expect(callback(login)[0]).to eq(401)
    expect(@profile_request).not_to have_been_requested
  end

  it "allows a valid authorized party with multiple audiences" do
    login = start_login
    stub_oauth(login, overrides: { "aud" => [client_id, "another-app"], "azp" => client_id })
    expect(callback(login)[0]).to eq(200)
  end

  %w[/.well-known/jwks.json /oauth/userinfo].each do |path|
    [401, 500].each do |status|
      it "handles #{path} returning HTTP #{status}" do
        login = start_login
        stub_oauth(login)
        stub_request(:get, "#{base_url}#{path}").to_return(status: status, body: "provider unavailable")
        expect(callback(login)[0]).to eq(401)
        expect(@auth).to be_nil
      end
    end

    it "handles #{path} timing out" do
      login = start_login
      stub_oauth(login)
      stub_request(:get, "#{base_url}#{path}").to_timeout
      expect(callback(login)[0]).to eq(401)
      expect(@auth).to be_nil
    end

    it "handles malformed JSON from #{path}" do
      login = start_login
      stub_oauth(login)
      stub_request(:get, "#{base_url}#{path}").to_return(
        headers: { "Content-Type" => "application/json" }, body: "{"
      )
      expect(callback(login)[0]).to eq(401)
      expect(@auth).to be_nil
    end
  end

  it "rejects a UserInfo response with no subject" do
    login = start_login
    profile.delete("sub")
    stub_oauth(login)
    expect(callback(login)[0]).to eq(401)
    expect(@auth).to be_nil
  end

  it "uses the configured callback path without incoming query parameters" do
    custom = described_class.new(app, client_id, client_secret, callback_path: "/custom/whop/callback")
    token = Rack::Protection::AuthenticityToken.token(session)
    response = custom.call(env_for("/auth/whop?campaign=example", method: "POST", params: { authenticity_token: token }))
    params = URI.decode_www_form(URI(response[1].fetch("location")).query).to_h
    expect(params["redirect_uri"]).to eq("http://example.org/custom/whop/callback")
  end
end
