# frozen_string_literal: true

require "cgi"
require "digest"
require "rack"
require "rack/protection"

module WhopDemo
  class Headers
    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, body = @app.call(env)
      headers = headers.merge(
        "x-content-type-options" => "nosniff", "referrer-policy" => "no-referrer",
        "x-frame-options" => "DENY", "cache-control" => "no-store",
        "content-security-policy" => "default-src 'none'; style-src 'self'; font-src 'self'; img-src 'self'; " \
                                     "base-uri 'none'; frame-ancestors 'none'; " \
                                     "form-action 'self' https://api.whop.com https://sandbox-api.whop.com " \
                                     "https://whop.com https://sandbox.whop.com"
      )
      headers["strict-transport-security"] = "max-age=31536000" if ENV["RACK_ENV"] == "production"
      [status, headers, body]
    end
  end

  # Permanently redirects browser requests on retired hostnames to the canonical origin.
  class LegacyHostRedirect
    def initialize(app, hosts:, origin:)
      @app = app
      @hosts = hosts
      @origin = origin
    end

    def call(env)
      request = Rack::Request.new(env)
      if @hosts.include?(request.host) && (request.get? || request.head?) && request.path != "/health"
        return [301, { "location" => "#{@origin}#{request.fullpath}", "cache-control" => "no-store" }, []]
      end

      @app.call(env)
    end
  end

  class App
    # Shared WhopTools navigation, vendored from whoptools/whoptools.com.
    KIT = File.expand_path("public/whoptools", __dir__)
    HEADER = File.read(File.join(KIT, "header.html")).strip
    FOOTER = File.read(File.join(KIT, "footer.html")).strip
    SOURCE_BUTTON = '<a class="wt-button wt-button--surface" href="https://github.com/whoptools/omniauth-whop">' \
                    "#{File.read(File.join(KIT, 'github.svg')).strip}Source code</a>".freeze
    # Versioned URLs stop browsers pairing new markup with a cached old stylesheet.
    ASSET = lambda do |path|
      "/assets/#{path}?v=#{Digest::SHA256.file(File.expand_path("public/#{path}", __dir__)).hexdigest[0, 10]}"
    end
    KIT_CSS = ASSET.call("whoptools/whoptools.css")
    FAVICON = ASSET.call("whoptools/favicon.svg")
    APP_CSS = ASSET.call("app.css")
    NOT_FOUND = <<~HTML
      <div class="wt-hero"><p class="wt-eyebrow">OmniAuth Whop · Ruby</p><h1 class="wt-title">Page not found.</h1>
      <div class="wt-actions"><a class="wt-button wt-button--surface" href="/">Go home</a></div></div>
    HTML

    def self.failure(_env)
      response(401, layout("Sign-in couldn’t be completed", <<~HTML))
        <div class="wt-hero"><p class="wt-eyebrow">OmniAuth Whop · Ruby</p><h1 class="wt-title">Sign-in didn’t finish.</h1>
        <p class="wt-lead">Canceled or not verified. Try again.</p>
        <div class="wt-actions"><a class="wt-button wt-button--surface" href="/">Back to sign in</a></div></div>
      HTML
    end

    def call(env)
      request = Rack::Request.new(env)
      return [200, { "content-type" => "text/plain" }, ["ok"]] if request.get? && request.path == "/health"

      session = env.fetch("rack.session")
      if request.get? && request.path == "/auth/whop/callback" && env["omniauth.auth"]
        auth = env.fetch("omniauth.auth")
        info = auth.fetch("info", {})
        session.clear
        session["profile"] = {
          "uid" => auth["uid"], "name" => info["name"], "nickname" => info["nickname"],
          "email" => info["email"], "email_verified" => info["email_verified"] == true
        }
        return redirect
      end
      if request.post? && request.path == "/logout"
        session.clear
        return redirect
      end
      return self.class.response(404, self.class.layout("Not found", NOT_FOUND)) unless request.get? && request.path == "/"

      token = Rack::Protection::AuthenticityToken.token(session)
      content = session["profile"] ? signed_in(session.fetch("profile"), token) : signed_out(token)
      self.class.response(200, self.class.layout("OmniAuth Whop · Sign in with Whop", content))
    end

    def self.response(status, html)
      [status, { "content-type" => "text/html; charset=utf-8", "cache-control" => "no-store" }, [html]]
    end

    def self.layout(title, content)
      <<~HTML
        <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta name="color-scheme" content="light dark"><title>#{CGI.escapeHTML(title)}</title>
        <link rel="icon" href="#{FAVICON}" type="image/svg+xml"><link rel="stylesheet" href="#{KIT_CSS}"><link rel="stylesheet" href="#{APP_CSS}"></head>
        <body class="wt-body"><a class="wt-skip" href="#main">Skip to content</a>#{HEADER}
        <main id="main" class="wt-main"><div class="wt-container">#{content}</div></main>
        #{FOOTER}</body></html>
      HTML
    end

    private

    def redirect
      [303, { "location" => "/", "cache-control" => "no-store" }, []]
    end

    def form(action, label, token, primary: true)
      <<~HTML
        <form method="post" action="#{action}"><input type="hidden" name="authenticity_token" value="#{CGI.escapeHTML(token)}">
        <button class="wt-button #{primary ? 'wt-button--solid' : 'wt-button--surface'}" type="submit">#{label}</button></form>
      HTML
    end

    def signed_out(token)
      <<~HTML
        <div class="wt-hero"><p class="wt-eyebrow">OmniAuth Whop · Ruby</p>
        <h1 class="wt-title">Sign in with Whop.</h1><p class="wt-lead">Real Whop login for any OmniAuth or Devise app.</p>
        <div class="wt-actions">#{form('/auth/whop', 'Sign in with Whop', token)}#{SOURCE_BUTTON}</div></div>
        <section class="wt-section"><h2>Install</h2><code class="wt-snippet">gem "omniauth-whop"</code>
        <p class="wt-muted note">PKCE, verified OpenID Connect tokens, sandbox support.</p></section>
      HTML
    end

    def signed_in(profile, token)
      rows = {
        "Whop user ID" => profile["uid"], "Name" => profile["name"], "Username" => profile["nickname"],
        "Email" => profile["email"], "Email verified" => profile["email_verified"] ? "Yes" : "Not confirmed"
      }.map do |label, value|
        "<div><dt>#{label}</dt><dd>#{CGI.escapeHTML(value.to_s.empty? ? 'Not provided' : value.to_s)}</dd></div>"
      end.join
      <<~HTML
        <div class="wt-hero"><p class="wt-eyebrow">OmniAuth Whop · Ruby <span class="wt-badge wt-badge--success">Signed in</span></p><h1 class="wt-title">You’re connected.</h1>
        <p class="wt-lead">Verified by OmniAuth. Here’s what your app receives.</p></div>
        <section class="wt-section"><h2>Profile</h2><dl class="profile">#{rows}</dl><div class="wt-actions">#{form('/logout', 'Sign out', token, primary: false)}</div></section>
      HTML
    end
  end
end
