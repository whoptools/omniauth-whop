#!/usr/bin/env bash
# Operator-run deployment of an explicitly reviewed repository revision.
set -euo pipefail
revision=${1:-}
if [[ ! $revision =~ ^[0-9a-f]{40}$ ]]; then
  echo 'Usage: hetzner.sh <40-character reviewed commit SHA>' >&2
  exit 64
fi
base=/opt/omniauth-whop
install -d -m 700 "$base/shared"
exec 9>"$base/shared/deploy.lock"
flock -w 900 9
test -s "$base/shared/runtime.env"
release="$base/releases/$revision"
previous=$(readlink -f "$base/current" || true)
activated=false
replacing=false
activate() {
  local directory=$1
  docker compose --project-name omniauth-whop --env-file "$directory/.env" -f "$directory/deploy/compose.yaml" up -d --no-build --wait --wait-timeout 120 app
  docker exec kamal-proxy kamal-proxy deploy whoptools-omniauth \
    --target omniauth-whop-app:9292 --host omniauth.whoptools.com --tls --health-check-path /health
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
replacing=true
activate "$release"
curl --fail --silent --show-error --retry 5 --retry-all-errors --retry-delay 2 \
  --resolve omniauth.whoptools.com:443:127.0.0.1 https://omniauth.whoptools.com/health >/dev/null
ln -sfn "$release" "$base/current"
activated=true
printf 'Deployed %s to https://omniauth.whoptools.com/\n' "$revision"
