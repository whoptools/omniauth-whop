# Security policy

Report suspected vulnerabilities privately through [GitHub private vulnerability reporting](https://github.com/whoptools/omniauth-whop/security/advisories/new) (**Security → Report a vulnerability**). Do not open public issues for exploitable problems.

## Supported versions

Fixes target the latest release on [RubyGems](https://rubygems.org/gems/omniauth-whop) and the `main` branch, which also runs the hosted demo at `omniauth.whoptools.com`.

## What to include

The gem version, Ruby/OmniAuth/Rails versions, a minimal reproduction, expected and actual behavior, and the boundary involved (PKCE, state, nonce, ID-token signature or claim validation, UserInfo subject matching, CSRF or session handling). Use your own Whop apps and accounts. Never include client secrets, authorization codes, access/refresh/ID tokens or real user data. If a credential was exposed, rotate it in Whop first.

You should receive an acknowledgement within a few days. Please allow time for a fix and release before public disclosure. This community project has not had an independent security audit.
