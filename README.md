# OmniAuth Whop

[![CI](https://github.com/whoptools/omniauth-whop/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/whoptools/omniauth-whop/actions/workflows/ci.yml)
[![Gem version](https://img.shields.io/gem/v/omniauth-whop?label=gem)](https://rubygems.org/gems/omniauth-whop)
[![Gem downloads](https://img.shields.io/gem/dt/omniauth-whop?label=downloads)](https://rubygems.org/gems/omniauth-whop)
[![Ruby 3.2+](https://img.shields.io/badge/Ruby-3.2%2B-CC342D)](omniauth-whop.gemspec)
[![MIT license](https://img.shields.io/github/license/whoptools/omniauth-whop)](LICENSE)
[![Live demo](https://img.shields.io/badge/live_demo-omniauth.whoptools.com-fa4616)](https://omniauth.whoptools.com/)

Add **Sign in with Whop** to a Ruby or Rails app.

A community-maintained [OmniAuth](https://github.com/omniauth/omniauth) strategy by [Yaroslav Shmarov](https://github.com/yshmarov). Not an official Whop integration or endorsed by Whop. For payments, see [pay-whop](https://github.com/whoptools/pay-whop).

<a href="https://whop.com/start/?code=CAKARK" rel="sponsored"><img src=".github/create-whop-account.svg" alt="Create a Whop account" height="40"></a>

- Authorization code flow with S256 PKCE and state validation.
- Fresh nonce for each login; concurrent sign-ins supported.
- ES256 ID token signature, issuer, audience, expiry, issued-at, nonce, and authorized-party validation.
- UserInfo subject checked against the verified ID token.
- Sandbox support. No Rails or Whop SDK dependency.

Requires Ruby 3.2+ and OmniAuth 2 (via `omniauth-oauth2`).

Verified with real Whop sandbox and production logins on November 15, 2026: authorization, code exchange, signature/claim validation, and UserInfo profile mapping. Fresh Rails applications also exercise both standalone OmniAuth and Devise integration in CI.

## Installation

```ruby
# Gemfile
gem "omniauth-whop"

# Rails applications also need request-phase CSRF protection:
gem "omniauth-rails_csrf_protection"
```

Then run `bundle install`.

## Configure your Whop app

1. Open your business's **Developer → Apps** page in [Whop sandbox](https://sandbox.whop.com/).
2. Create an app and open its OAuth settings. Use a name such as `OmniAuth Ruby Sandbox`; Whop rejects app names containing `whop`.
3. Register your exact callback URL, including protocol and path:
   - Rails: `http://localhost:3000/auth/whop/callback`
   - Devise: `http://localhost:3000/users/auth/whop/callback`
   - Included Rack demo: `http://localhost:9292/auth/whop/callback`
4. Save the app's client ID and client secret as `WHOP_CLIENT_ID` and `WHOP_CLIENT_SECRET`.
5. Under **Permissions**, add `oauth:token_exchange`, enter a short explanation, and save. This app API key permission enables the client secret to exchange authorization codes. It is separate from the user-facing `openid profile email` OAuth scopes. See [Whop's authentication guide](https://whop.com/blog/add-user-authentication/).

Use credentials from the same environment as the strategy. Register an HTTPS callback for production and omit `sandbox: true`.

## Rails

```ruby
# config/initializers/omniauth.rb
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :whop,
           ENV.fetch("WHOP_CLIENT_ID"),
           ENV.fetch("WHOP_CLIENT_SECRET"),
           sandbox: ENV["WHOP_SANDBOX"] == "true"
end
```

Initiate sign-in with a POST form:

```erb
<%= button_to "Sign in with Whop", "/auth/whop", data: { turbo: false } %>
```

Route `GET /auth/whop/callback` to your sessions controller and read `request.env["omniauth.auth"]`. Route `GET /auth/failure` to your failure handler. Your application owns account creation, account linking, and its login session.

Use `(provider, uid)` as the external identity. Do not automatically link existing accounts using an unverified email address. Email, name, nickname, and image may be absent.

## Devise

Use Devise's configuration instead of installing the middleware a second time:

```ruby
# config/initializers/devise.rb
config.omniauth :whop,
                ENV.fetch("WHOP_CLIENT_ID"),
                ENV.fetch("WHOP_CLIENT_SECRET"),
                sandbox: ENV["WHOP_SANDBOX"] == "true"
```

Add `:omniauthable, omniauth_providers: [:whop]` to your existing `devise` declaration, register an OmniAuth callbacks controller in your Devise routes, and implement its `whop` action using `request.env["omniauth.auth"]`.

```erb
<%= button_to "Sign in with Whop", user_whop_omniauth_authorize_path,
              data: { turbo: false } %>
```

Keep `omniauth-rails_csrf_protection` installed for Devise too.

## Auth hash

```ruby
{
  provider: "whop",
  uid: "user_example",
  info: {
    name: "Example User",
    nickname: "example",
    email: "example@example.com",
    email_verified: true,
    image: "https://example.com/avatar.png"
  },
  credentials: {
    token: "ACCESS_TOKEN",
    refresh_token: "REFRESH_TOKEN", # when provided
    expires_at: 1_800_000_000,       # when provided
    expires: true
  },
  extra: {
    raw_info: { "sub" => "user_example", "..." => "..." }
  }
}
```

Tokens are credentials. Keep them out of logs and browser responses; encrypt them at rest if your application needs to retain them. This strategy authenticates users; checking purchases or membership access is a separate application concern.

## Options

| Option | Default | Purpose |
| --- | --- | --- |
| `sandbox` | `false` | Use `https://sandbox-api.whop.com` for OAuth, UserInfo, and signing keys. Pass a Ruby boolean. |
| `scope` | `"openid profile email"` | Space-separated scopes. `openid` is always included because identity tokens are validated. |
| `issuer` | `"https://api.whop.com"` | Expected signed ID token issuer. Whop's sandbox discovery document advertises the same issuer. |
| `client_options` | Whop endpoints | Standard `omniauth-oauth2` client options. Requests default to 5-second connect and 15-second request timeouts. |

Leave PKCE and state validation enabled. The strategy fetches signing keys from the configured environment for each login, avoiding stale-key failures after rotation. Identity comes from a verified ID token plus the authenticated UserInfo endpoint; it never trusts a decoded, unverified JWT.

## Try the demo

[Sign in with Whop](https://omniauth.whoptools.com) on the hosted demo. It uses production Whop login and runs on our existing Hetzner server. See the [deployment runbook](docs/hetzner.md).

## Run the sandbox demo

```sh
git clone https://github.com/whoptools/omniauth-whop.git
cd omniauth-whop
bundle install
cp .env.example .env
# Set the sandbox client ID and secret in .env.
bundle exec rackup examples/config.ru --host localhost --port 9292
```

Open `http://localhost:9292` and click **Sign in with Whop**. The demo displays the verified user ID and profile, with CSRF-protected sign-out. It does not display or save access/refresh tokens. Its encrypted session lasts one hour; set `SESSION_SECRET` to a random value of at least 64 bytes to preserve sessions across restarts. Production requires a stable secret and an HTTPS `PUBLIC_URL`.

The interface uses the shared WhopTools kit in `examples/public/whoptools/` (Frosted UI colors, Inter, shared header and footer), vendored from [whoptools.com](https://github.com/whoptools/whoptools.com). It follows the system light/dark theme automatically.

## Development

```sh
bundle install
bundle exec rake
bundle exec rubocop
bundle exec ruby bin/test_rails
gem build omniauth-whop.gemspec
```

Tests exercise the real OmniAuth middleware and HTTP boundary with generated signing keys and stubbed Whop responses. External HTTP is disabled in the test suite. CI runs Ruby 3.2, 3.3, 3.4, and 4.0, plus the minimum supported JWT/OmniAuth dependencies. The Rails integration matrix covers Rails 7.2/Devise 4.9, Rails 8.0/Devise 5, and Rails 8.1/Devise 5.

`bin/test_rails` builds and installs the packaged gem into a temporary fresh Rails application. It checks POST initiation with a real Rails CSRF token, signed callbacks, persisted sessions, callback replay, and missing CSRF tokens in both standalone and Devise configurations. Set `RAILS_VERSION` and `DEVISE_VERSION` to select another supported combination; set `GEM_ARTIFACT` to test a previously built `.gem`. Whop HTTP responses are stubbed, so this command does not need credentials.

See [CONTRIBUTING.md](CONTRIBUTING.md) for checks and the Trusted Publishing release process.

Report bugs with a minimal reproduction, Ruby/gem versions, and the failure type. Do not include credentials, authorization codes, or customer data. To report a security issue privately, use [GitHub's security advisory form](https://github.com/whoptools/omniauth-whop/security/advisories/new).

## License

[MIT](LICENSE)

## Part of WhopTools

Open-source Whop integrations. More at [whoptools.com](https://whoptools.com).

| Project | Live demo | Source |
| --- | --- | --- |
| Whop Checkout for Webflow | [wf-checkout.whoptools.com](https://wf-checkout.whoptools.com/) | [webflow-whop](https://github.com/whoptools/webflow-whop) |
| OmniAuth Whop | [omniauth.whoptools.com](https://omniauth.whoptools.com/) | [omniauth-whop](https://github.com/whoptools/omniauth-whop) |
| Pay Whop | [pay-rails.whoptools.com](https://pay-rails.whoptools.com/) | [pay-whop](https://github.com/whoptools/pay-whop) |
