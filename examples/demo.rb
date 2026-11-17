# frozen_string_literal: true

require "cgi"
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
        "content-security-policy" => "default-src 'none'; style-src 'self'; font-src 'self'; " \
                                     "base-uri 'none'; frame-ancestors 'none'; " \
                                     "form-action 'self' https://api.whop.com https://sandbox-api.whop.com " \
                                     "https://whop.com https://sandbox.whop.com"
      )
      headers["strict-transport-security"] = "max-age=31536000" if ENV["RACK_ENV"] == "production"
      [status, headers, body]
    end
  end

  class App
    def self.failure(_env)
      response(401, layout("Sign-in couldn’t be completed", <<~HTML))
        <div class="hero"><p class="eyebrow">OmniAuth Whop</p><h1>Let’s try that again.</h1>
        <p class="lead">Your sign-in was canceled or couldn’t be verified.</p>
        <a class="button primary" href="/">Back to sign in</a></div>
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
      unless request.get? && request.path == "/"
        return self.class.response(404,
                                   self.class.layout("Not found",
                                                     '<div class="hero"><h1>Page not found</h1><a href="/">Go home</a></div>'))
      end

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
        <title>#{CGI.escapeHTML(title)}</title><link rel="stylesheet" href="/assets/app.css"></head><body><main>
        <header class="topbar"><a class="brand" href="https://whoptools.com">WhopTools</a><span class="product">OmniAuth Whop</span><a class="button primary signup" href="https://whop.com/start/?code=CAKARK" rel="sponsored nofollow">Create a Whop account</a></header>
        #{content}
        <footer><nav aria-label="Resources"><a href="https://github.com/whoptools/omniauth-whop">Source &amp; setup</a>
        <a href="https://rubygems.org/gems/omniauth-whop">RubyGems</a><a href="https://whoptools.com">More tools</a></nav>
                </footer></main></body></html>
      HTML
    end

    private

    def redirect
      [303, { "location" => "/", "cache-control" => "no-store" }, []]
    end

    def form(action, label, token, primary: true)
      <<~HTML
        <form method="post" action="#{action}"><input type="hidden" name="authenticity_token" value="#{CGI.escapeHTML(token)}">
        <button class="#{primary ? 'primary' : 'secondary'}" type="submit">#{label}</button></form>
      HTML
    end

    def signed_out(token)
      <<~HTML
        <div class="hero"><p class="eyebrow"><span class="mark" aria-hidden="true">W</span>Authentication for Ruby &amp; Rails</p>
        <h1>Sign in with Whop.</h1><p class="lead">Try a real Whop login, then add it to your Ruby or Rails app with OmniAuth.</p>
        <div class="actions">#{form('/auth/whop', 'Sign in with Whop', token)}<a href="https://github.com/whoptools/omniauth-whop#installation">Add it to your app ↗</a></div></div>
        <section><h2>One sign-in. Your verified profile.</h2><ol class="steps"><li>Sign in securely on Whop.</li>
        <li>Return here to see your verified account details.</li><li>Sign out to clear this demo’s session.</li></ol></section>
        <section><h2>Start with one gem</h2><p class="snippet"><code>gem "omniauth-whop"</code></p>
        <p class="lead">Works with OmniAuth and Devise. Includes PKCE and verified OpenID Connect identity tokens.</p></section>
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
        <div class="hero"><p class="eyebrow status">Signed in successfully</p><h1>You’re connected.</h1>
        <p class="lead">Your Whop identity was verified by OmniAuth.</p></div>
        <section><h2>Your profile</h2><dl class="profile">#{rows}</dl><div class="actions">#{form('/logout', 'Sign out', token, primary: false)}</div></section>
      HTML
    end
  end
end
