# frozen_string_literal: true

require "bundler/setup"
require "omniauth-whop"
require "webmock/rspec"
require "rack/mock"
require "logger"

WebMock.disable_net_connect!
OmniAuth.config.logger = Logger.new(IO::NULL)
OmniAuth.config.on_failure = lambda do |env|
  [401, { "content-type" => "text/plain" }, [env["omniauth.error.type"].to_s]]
end
