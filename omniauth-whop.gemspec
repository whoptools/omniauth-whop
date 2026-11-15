# frozen_string_literal: true

require_relative "lib/omniauth/whop/version"

Gem::Specification.new do |spec|
  spec.name = "omniauth-whop"
  spec.version = OmniAuth::Whop::VERSION
  spec.authors = ["Yaroslav Shmarov"]
  spec.email = ["yshmarov@gmail.com"]
  spec.summary = "Sign in with Whop for OmniAuth"
  spec.description = "A community OmniAuth strategy for Whop with PKCE, verified OpenID Connect ID tokens, and sandbox support."
  spec.homepage = "https://github.com/yshmarov/omniauth-whop"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"
  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE", "CHANGELOG.md"]
  spec.require_paths = ["lib"]
  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }
  spec.add_dependency "jwt", ">= 2.9", "< 4"
  spec.add_dependency "omniauth-oauth2", "~> 1.10", ">= 1.10.1"
end
