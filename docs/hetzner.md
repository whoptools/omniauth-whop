# OmniAuth Whop demo on Hetzner

The Rack demo runs at **https://omniauth.whoptools.com** on the existing Corsego server (`188.245.75.73`), alongside Pay and Webflow. It uses Whop's production OAuth environment. No new server is required.

## Interface

The server-rendered interface uses pinned `@frosted-ui/colors` and self-hosted Inter following the [WhopTools style guide](https://github.com/whoptools/whoptools.com/blob/main/STYLE_GUIDE.md). CSS follows the system's light/dark preference automatically. There is no theme picker, saved override, or client-side JavaScript.

## Runtime

- Container: `omniauth-whop-app`, private port 9292 on the existing `kamal` Docker network.
- Limits: 256 MB memory, 0.25 CPU, bounded logs, automatic restart and health checks.
- Releases: `/opt/omniauth-whop/releases/<commit>`; `current` points to the active release.
- Secrets: `/opt/omniauth-whop/shared/runtime.env`, root-owned mode 0600, outside all build contexts.
- HTTPS: existing Kamal Proxy; DNS A record `omniauth` points to `188.245.75.73`.

Required runtime variables:

```dotenv
RACK_ENV=production
PUBLIC_URL=https://omniauth.whoptools.com
WHOP_SANDBOX=false
WHOP_CLIENT_ID=app_example
WHOP_CLIENT_SECRET=replace-on-server
SESSION_SECRET=replace-with-at-least-64-random-bytes
```

Register `https://omniauth.whoptools.com/auth/whop/callback` in the existing production Whop OAuth app, retaining local callbacks. The canonical origin is fixed by `PUBLIC_URL`; inbound host headers do not choose the OAuth callback destination.

The demo retains only selected profile fields in an encrypted, HttpOnly, Secure, SameSite=Lax cookie for one hour. It does not store access/refresh tokens or use a database. Sign-out clears the demo session; it does not sign the visitor out of Whop. Preserve `SESSION_SECRET` across deployments. Rotating it signs demo visitors out.

## Deploy and rollback

CI builds the production image and checks the HTTP/authentication boundary. Deployment is operator-run; opening or merging a PR does not automatically deploy it. The initial hosting request permits deploying the reviewed PR revision before merge; PR merges still require the owner's explicit instruction.

After tests and local visual review, push the revision and run on the server:

```sh
bash /path/to/reviewed/deploy/hetzner.sh <40-character-commit-SHA>
```

The script downloads that exact revision, uses a dedicated resource-limited builder, activates the container, verifies HTTPS health, and advances `current`. Failed upgrades restore the previous release when one exists. It does not restart Pay, Webflow, Corsego, or the shared proxy. Container replacement can briefly interrupt requests. To roll back, run the same command with the previous reviewed commit.

Do not commit secrets or copy `.env` files into a Docker build. The application has no persistent database to back up; retain the server environment file securely.
