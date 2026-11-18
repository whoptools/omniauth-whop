# frozen_string_literal: true

require "bundler/setup"
require "dotenv/load"
require "omniauth-whop"
require "rack/session/cookie"
require "rack/protection"
require "uri"
require_relative "demo"

production = ENV["RACK_ENV"] == "production"
secret = production ? ENV.fetch("SESSION_SECRET") : ENV.fetch("SESSION_SECRET") { SecureRandom.hex(64) }
raise "SESSION_SECRET must contain at least 64 bytes" if secret.bytesize < 64

if production
  url = URI.parse(ENV.fetch("PUBLIC_URL"))
  origin_only = [nil, "", "/"].include?(url.path) && !url.query && !url.fragment && !url.userinfo
  raise "PUBLIC_URL must be an HTTPS origin" unless url.scheme == "https" && url.host && origin_only

  OmniAuth.config.full_host = url.to_s.delete_suffix("/")
end
# Retired hostnames (comma-separated) redirect to PUBLIC_URL; health checks stay in place.
legacy_hosts = ENV.fetch("LEGACY_HOSTS", "").split(",").map(&:strip).reject(&:empty?)

use WhopDemo::Headers
use WhopDemo::LegacyHostRedirect, hosts: legacy_hosts, origin: OmniAuth.config.full_host if production && legacy_hosts.any?
map "/assets" do
  run Rack::Files.new(File.expand_path("public", __dir__))
end
map "/" do
  use Rack::Session::Cookie, key: "omniauth_whop_demo", secret: secret, same_site: :lax,
                             httponly: true, secure: production, expire_after: 3600
  use Rack::Protection::AuthenticityToken
  use OmniAuth::Builder do
    provider :whop, ENV.fetch("WHOP_CLIENT_ID"), ENV.fetch("WHOP_CLIENT_SECRET"),
             sandbox: ENV.fetch("WHOP_SANDBOX", "true") == "true"
  end
  OmniAuth.config.on_failure = WhopDemo::App.method(:failure)
  run WhopDemo::App.new
end
