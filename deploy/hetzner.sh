#!/usr/bin/env bash
# Called by the restricted GitHub Actions SSH account.
set -euo pipefail
if [[ $# != 1 || ${1:-} != deploy\ * ]] || [[ ! ${1#deploy } =~ ^[0-9a-f]{40}$ ]]; then
  echo 'Expected: deploy <40-character commit SHA>' >&2
  exit 64
fi
revision=${1#deploy }
base=/opt/omniauth-whop
repository=https://github.com/whoptools/omniauth-whop.git
# Share the build/activation lock with Pay and Webflow on this server.
exec 9>/opt/pay-whop/shared/deploy.lock
flock -w 1800 9
latest=$(git ls-remote "$repository" refs/heads/main | cut -f1)
if [[ $revision != "$latest" ]]; then
  echo 'Skipping a superseded main revision.'
  exit 0
fi
test -s "$base/shared/runtime.env"
release="$base/releases/$revision"
previous=$(readlink -f "$base/current" || true)
activated=false
replacing=false
activate() {
  local directory=$1
  docker compose --project-name omniauth-whop --env-file "$directory/.env" -f "$directory/deploy/compose.yaml" up -d --no-build --wait --wait-timeout 120 app
  docker exec kamal-proxy kamal-proxy deploy whoptools-omniauth \
    --target omniauth-whop-app:9292 --host omniauth-ruby.whoptools.com --host omniauth.whoptools.com \
    --tls --health-check-path /health
}
cleanup() {
  local result=$?
  trap - EXIT
  docker buildx stop omniauth-whop-builder >/dev/null 2>&1 || true
  if [[ $result != 0 && $replacing == true && $activated == false && -d $previous ]]; then
    echo 'Restoring the previous application release.' >&2
    activate "$previous" || echo 'Rollback requires operator intervention.' >&2
  fi
  exit "$result"
}
trap cleanup EXIT
install -d "$release"
curl --fail --silent --show-error --location --retry 3 \
  "https://codeload.github.com/whoptools/omniauth-whop/tar.gz/$revision" \
  | tar -xz --strip-components=1 -C "$release"
printf 'APP_IMAGE_TAG=%s\n' "$revision" > "$release/.env"
if ! docker buildx inspect omniauth-whop-builder >/dev/null 2>&1; then
  docker buildx create --name omniauth-whop-builder --driver docker-container \
    --driver-opt memory=768m,memory-swap=1g,cpu-quota=100000,cpu-period=100000
fi
docker buildx build --builder omniauth-whop-builder --load \
  -t "omniauth-whop:$revision" -f "$release/deploy/Dockerfile" "$release"
docker buildx stop omniauth-whop-builder
# Do not activate a stale run if main changed while its image built.
latest=$(git ls-remote "$repository" refs/heads/main | cut -f1)
if [[ $revision != "$latest" ]]; then
  echo 'Skipping activation of a superseded main revision.'
  exit 0
fi
replacing=true
activate "$release"
curl --fail --silent --show-error --retry 5 --retry-all-errors --retry-delay 2 \
  --resolve omniauth-ruby.whoptools.com:443:127.0.0.1 https://omniauth-ruby.whoptools.com/health >/dev/null
ln -sfn "$release" "$base/current"
activated=true
printf 'Deployed %s to https://omniauth-ruby.whoptools.com/\n' "$revision"
