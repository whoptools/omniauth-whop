# Contributing

Use Ruby 3.2 or newer. Keep credentials in ignored local environment files; never
include tokens, authorization codes, or real user profiles in fixtures or issues.

```sh
bundle install
bundle exec rake
bundle exec rubocop
bundle exec ruby bin/test_rails
BUNDLE_GEMFILE=gemfiles/minimum.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/minimum.gemfile bundle exec rake spec
```

The Rails harness generates temporary apps and tests the built gem in both plain
Rails and Devise configurations. It uses generated signing keys and stubbed HTTP,
with network access disabled while the login checks run. Dependency installation
requires internet access. CI covers the Ruby and Rails combinations in
`.github/workflows/ci.yml`.

For a real provider check, use `examples/config.ru` with your own Whop app. Test
sandbox and production separately, using matching credentials and callback URLs.
The demo only displays identity information; it does not persist access tokens.

## Whop signup links

Use [Yaroslav's production Whop referral link](https://whop.com/start/?code=CAKARK)
for reader-facing signup links in documentation and demos. Yaroslav may earn a
commission from signups through this link; keep that disclosure beside each link.
Use `rel="sponsored nofollow"` for HTML links. Preserve technical documentation,
sandbox, API, OAuth and callback URLs, and keep code examples functional.

## Releases (maintainer)

1. Update `lib/omniauth/whop/version.rb` and `CHANGELOG.md` in a pull request.
2. Review the changes, wait for CI, and merge the pull request manually.
3. From an up-to-date, clean `main`, create and push `vVERSION`, matching the gem
   version. Do not tag an unmerged branch.
4. Watch the Release workflow. It runs all CI checks, confirms that the tag is
   on `main`, and publishes through RubyGems Trusted Publishing. Verify the new
   version on RubyGems, then write the GitHub release notes.

The publisher is bound to `yshmarov/omniauth-whop`, workflow `release.yml`, and
GitHub environment `release`. The environment permits `v*` tags. No long-lived
RubyGems API key belongs in GitHub secrets. Changing the workflow filename or
environment requires updating the RubyGems publisher as well.

Publishing is irreversible for a version number. If a release fails, inspect
RubyGems before rerunning the workflow; do not try to overwrite an existing gem.
Dependabot proposes weekly dependency and GitHub Actions updates for review.

## Security reports

Use the repository's [private vulnerability reporting form](https://github.com/yshmarov/omniauth-whop/security/advisories/new).
For ordinary bugs, open an issue with versions and a minimal reproduction.
