# frozen_string_literal: true

require "omniauth-oauth2"
require "jwt"

module OmniAuth
  module Strategies
    # Whop OAuth authorization-code flow with PKCE and verified OIDC identity.
    class Whop < OAuth2
      option :name, "whop"
      option :scope, "openid profile email"
      option :pkce, true
      option :sandbox, false
      # Whop's sandbox discovery document also advertises this issuer.
      option :issuer, "https://api.whop.com"
      option :client_options, {
        site: "https://api.whop.com",
        authorize_url: "/oauth/authorize",
        token_url: "/oauth/token",
        auth_scheme: :request_body,
        connection_opts: { request: { timeout: 15, open_timeout: 5 } }
      }

      uid { raw_info.fetch("sub") }

      info do
        {
          name: raw_info["name"],
          nickname: raw_info["preferred_username"],
          email: raw_info["email"],
          image: raw_info["picture"],
          email_verified: raw_info["email_verified"]
        }.compact
      end

      extra { { raw_info: raw_info } }

      def client
        oauth_client = super
        oauth_client.site = "https://sandbox-api.whop.com" if options.sandbox
        oauth_client
      end

      def authorize_params
        params = super
        params[:scope] = (["openid"] + params[:scope].to_s.split).uniq.join(" ")
        params[:nonce] = SecureRandom.urlsafe_base64(32)
        nonces = session.fetch("omniauth.whop.nonces", {}).dup
        nonces[params.fetch(:state)] = params[:nonce]
        session["omniauth.whop.nonces"] = nonces.to_a.last(3).to_h
        params
      end

      def callback_phase
        nonces = session.fetch("omniauth.whop.nonces", {}).dup
        @expected_nonce = nonces.delete(request.params["state"])
        session["omniauth.whop.nonces"] = nonces
        super
      rescue JWT::DecodeError, JSON::ParserError, KeyError => e
        fail!(:invalid_credentials, CallbackError.new(:invalid_identity, e.class.name))
      end

      def raw_info
        @raw_info ||= begin
          profile = access_token.get("/oauth/userinfo").parsed
          unless profile.is_a?(Hash) && profile["sub"] == @id_token_claims.fetch("sub")
            raise CallbackError.new(:invalid_identity, "UserInfo subject does not match ID token")
          end

          profile
        end
      end

      def callback_url
        full_host + callback_path
      end

      protected

      def build_access_token
        token = super
        validate_id_token!(token.params["id_token"])
        token
      end

      def validate_id_token!(id_token)
        if id_token.to_s.empty? || @expected_nonce.to_s.empty?
          raise CallbackError.new(:invalid_identity,
                                  "Missing ID token or nonce")
        end

        jwks = client.request(:get, "/.well-known/jwks.json", parse: :json, snaky: false).parsed
        @id_token_claims = JWT.decode(
          id_token, nil, true,
          algorithms: ["ES256"], jwks: jwks,
          iss: options.issuer, verify_iss: true,
          aud: options.client_id, verify_aud: true,
          verify_iat: true, required_claims: %w[iss sub aud exp iat nonce]
        ).first
        unless secure_compare(@id_token_claims["nonce"].to_s, @expected_nonce)
          raise CallbackError.new(:invalid_identity, "ID token nonce mismatch")
        end
        raise CallbackError.new(:invalid_identity, "Missing ID token subject") if @id_token_claims["sub"].to_s.empty?

        audiences = Array(@id_token_claims["aud"])
        authorized_party = @id_token_claims["azp"]
        return unless (audiences.size > 1 || authorized_party) && authorized_party != options.client_id

        raise CallbackError.new(:invalid_identity, "ID token authorized party mismatch")
      end
    end
  end
end
