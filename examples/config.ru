# frozen_string_literal: true

require "bundler/setup"
require "dotenv/load"
require "omniauth-whop"
require "rack/session/cookie"
require "rack/protection"
require "cgi"
require "json"

# Demo only: keep access and refresh tokens out of the session and response.
use Rack::Session::Cookie,
    key: "omniauth_whop_demo",
    secret: ENV.fetch("SESSION_SECRET") { SecureRandom.hex(64) },
    same_site: :lax,
    httponly: true,
    secure: ENV["RACK_ENV"] == "production"

use OmniAuth::Builder do
  provider :whop, ENV.fetch("WHOP_CLIENT_ID"), ENV.fetch("WHOP_CLIENT_SECRET"),
           sandbox: ENV.fetch("WHOP_SANDBOX", "true") == "true"
end

OmniAuth.config.on_failure = lambda do |_env|
  [401, { "content-type" => "text/html", "cache-control" => "no-store" },
   ['<h1>Whop sign-in failed</h1><p><a href="/">Try again</a></p>']]
end

run lambda { |env|
  headers = { "content-type" => "text/html; charset=utf-8", "cache-control" => "no-store" }
  if env["omniauth.auth"]
    auth = env.fetch("omniauth.auth")
    profile = { provider: auth.provider, uid: auth.uid, info: auth.info.to_h }
    html = "<h1>Signed in with Whop</h1><pre>#{CGI.escapeHTML(JSON.pretty_generate(profile))}</pre>"
    [200, headers, [html]]
  elsif env["PATH_INFO"] == "/"
    token = Rack::Protection::AuthenticityToken.token(env.fetch("rack.session"))
    [200, headers, [<<~HTML]]
      <!doctype html><html lang="en"><meta charset="utf-8"><title>OmniAuth Whop demo</title>
      <h1>OmniAuth Whop demo</h1>
      <form method="post" action="/auth/whop">
        <input type="hidden" name="authenticity_token" value="#{CGI.escapeHTML(token)}">
        <button type="submit">Sign in with Whop</button>
      </form></html>
    HTML
  else
    [404, headers, ["Not found"]]
  end
}
