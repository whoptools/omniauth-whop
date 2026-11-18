# OmniAuth Whop demo on Hetzner

The Rack demo runs at **https://omniauth-ruby.whoptools.com** on the existing Corsego server (`188.245.75.73`), alongside Pay and Webflow. It uses Whop's production OAuth environment. No new server is required.

## Interface

The server-rendered interface uses pinned `@frosted-ui/colors` and self-hosted Inter following the [WhopTools style guide](https://github.com/whoptools/whoptools.com/blob/main/STYLE_GUIDE.md). CSS follows the system's light/dark preference automatically. There is no theme picker, saved override, or client-side JavaScript.

## Runtime

- Container: `omniauth-whop-app`, private port 9292 on the existing `kamal` Docker network.
- Limits: 256 MB memory, 0.25 CPU, bounded logs, automatic restart and health checks.
- Releases: `/opt/omniauth-whop/releases/<commit>`; `current` points to the active release.
- Secrets: `/opt/omniauth-whop/shared/runtime.env`, root-owned mode 0600, outside all build contexts.
- HTTPS: existing Kamal Proxy; DNS A records `omniauth-ruby` (canonical) and `omniauth` (legacy, redirects) point to `188.245.75.73`.

Required runtime variables:

```dotenv
RACK_ENV=production
PUBLIC_URL=https://omniauth-ruby.whoptools.com
LEGACY_HOSTS=omniauth.whoptools.com
WHOP_SANDBOX=false
WHOP_CLIENT_ID=app_example
WHOP_CLIENT_SECRET=replace-on-server
SESSION_SECRET=replace-with-at-least-64-random-bytes
```

Register `https://omniauth-ruby.whoptools.com/auth/whop/callback` in the existing production Whop OAuth app, retaining local callbacks. The previous `https://omniauth.whoptools.com/auth/whop/callback` stays registered until the November 18, 2026 cutover has been stable for a week. Browser requests to the legacy host get a 301 to `PUBLIC_URL`; `/health` is served in place. The canonical origin is fixed by `PUBLIC_URL`; inbound host headers do not choose the OAuth callback destination.

The demo retains only selected profile fields in an encrypted, HttpOnly, Secure, SameSite=Lax cookie for one hour. It does not store access/refresh tokens or use a database. Sign-out clears the demo session; it does not sign the visitor out of Whop. Preserve `SESSION_SECRET` across deployments. Rotating it signs demo visitors out.

## Automatic deployments

Every push or merge to `main` runs the complete CI matrix. Only a successful matrix starts **Deploy to Hetzner**. Pull requests run tests without receiving deployment credentials. The first automatic rollout is verified after merging PR #4.

Repository secrets `HETZNER_DEPLOY_KEY` and `HETZNER_KNOWN_HOSTS` hold a dedicated SSH key and the pinned server host key. The `omniauth-whop-deploy` Unix account uses a forced command, no interactive shell or forwarding, and one allowed sudo entry: the root-owned `/usr/local/sbin/omniauth-whop-deploy` script. Application secrets remain on the server.

The installed script accepts only `deploy <40-character commit SHA>` for current `main`, checks again after building, and skips superseded runs. Deployments share the server lock used by Pay and Webflow. GitHub also serializes this repository's deployment jobs. Build and activation use the existing resource limits; failed upgrades restore the previous release when available. Container replacement can briefly interrupt requests.

Retry a failed rollout through GitHub Actions after checking its error. To deploy the current, CI-verified main revision manually:

```sh
ssh root@188.245.75.73 "/usr/local/sbin/omniauth-whop-deploy 'deploy <40-character SHA>'"
```

Changes to `deploy/hetzner.sh` require an operator to install the reviewed script at `/usr/local/sbin/omniauth-whop-deploy` (root-owned, mode 0755). The restricted CI account cannot update this script or rotate its key.

## Rollback

The automatic command deliberately rejects older revisions. An operator can restore a retained release by using its `.env` and `deploy/compose.yaml` with `docker compose up -d --no-build --wait app`, refreshing the `whoptools-omniauth` Kamal Proxy target, verifying HTTPS health, and restoring the `current` symlink. Coordinate this under the same shared deployment lock. Preserve the runtime environment and session secret.

Do not commit secrets or copy `.env` files into a Docker build. The application has no persistent database to back up; retain the server environment file securely.
