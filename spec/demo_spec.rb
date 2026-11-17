# frozen_string_literal: true

require "spec_helper"
require_relative "../examples/demo"

RSpec.describe WhopDemo::App do
  let(:session) { {} }
  let(:app) { WhopDemo::Headers.new(Rack::Protection::AuthenticityToken.new(described_class.new)) }

  def request(path, method: "GET", params: {}, extra: {})
    app.call(Rack::MockRequest.env_for("https://example.org#{path}", method: method, params: params)
                             .merge("rack.session" => session).merge(extra))
  end

  it "keeps only profile fields in the session and redirects away from callback credentials" do
    auth = OmniAuth::AuthHash.new(provider: "whop", uid: "user_123",
                                  info: { name: "<script>alert(1)</script>", email: "demo@example.com", email_verified: true },
                                  credentials: { token: "sensitive-access-token", refresh_token: "sensitive-refresh-token" },
                                  extra: { raw_info: { secret: "private" } })
    status, headers, = request("/auth/whop/callback?code=sensitive-code", extra: { "omniauth.auth" => auth })
    expect(status).to eq(303)
    expect(headers.fetch("location")).to eq("/")
    expect(session.keys).to eq(["profile"])
    expect(session.fetch("profile").keys).to contain_exactly("uid", "name", "nickname", "email", "email_verified")
    body = request("/")[2].join
    expect(body).to include("&lt;script&gt;", "demo@example.com")
    expect(body).not_to include("<script>", "sensitive-", "private")
  end

  it "requires a CSRF token for sign-out and clears the session on valid sign-out" do
    session["profile"] = { "uid" => "user_123" }
    expect(request("/logout", method: "POST")[0]).to eq(403)
    expect(session).to have_key("profile")
    token = Rack::Protection::AuthenticityToken.token(session)
    expect(request("/logout", method: "POST", params: { authenticity_token: token })[0]).to eq(303)
    expect(session).to be_empty
  end

  it "does not accept GET sign-out or a callback without verified authentication" do
    expect(request("/logout")[0]).to eq(404)
    expect(request("/auth/whop/callback")[0]).to eq(404)
  end

  it "serves health without an authenticated profile" do
    response = request("/health")
    expect(response[0]).to eq(200)
    expect(response[2]).to eq(["ok"])
  end

  it "prevents caching, framing, and referrer leakage on profile responses" do
    headers = request("/")[1]
    expect(headers).to include("cache-control" => "no-store", "referrer-policy" => "no-referrer", "x-frame-options" => "DENY")
    expect(headers.fetch("content-security-policy")).to include("frame-ancestors 'none'")
  end

  it "shows a recoverable failure without reflecting provider errors" do
    status, _, body = described_class.failure("omniauth.error" => "sensitive-provider-detail")
    expect(status).to eq(401)
    expect(body.join).to include("Back to sign in")
    expect(body.join).not_to include("sensitive-provider-detail")
  end
end
