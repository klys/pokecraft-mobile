#!/usr/bin/env bash
#
# Builds the PokeCraft web client (client-poke.io) and copies the production
# bundle into ./www so Capacitor can wrap it.
#
# Environment variables:
#   WEB_SRC       Path to the client-poke.io checkout. Default: ../client-poke.io
#   CONFIG_JSON   Optional. If set, its contents replace public/config.json
#                 before the build (used by CI to inject the mobile backend URL).
#
set -euo pipefail

MOBILE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_SRC="${WEB_SRC:-$MOBILE_DIR/../client-poke.io}"

if [ ! -d "$WEB_SRC" ]; then
  echo "error: web source not found at '$WEB_SRC'." >&2
  echo "       set WEB_SRC to your client-poke.io checkout." >&2
  exit 1
fi

WEB_SRC="$(cd "$WEB_SRC" && pwd)"
echo "==> Building web client from: $WEB_SRC"

pushd "$WEB_SRC" >/dev/null

if [ -n "${CONFIG_JSON:-}" ]; then
  echo "==> Overwriting public/config.json from \$CONFIG_JSON"
  printf '%s' "$CONFIG_JSON" > public/config.json
fi

if [ -f package-lock.json ]; then
  npm ci
else
  npm install
fi
npm run build

popd >/dev/null

echo "==> Copying build output into www/"
rm -rf "$MOBILE_DIR/www"
cp -r "$WEB_SRC/build" "$MOBILE_DIR/www"

# Game assets now live in ../asset-storage and are streamed at runtime
# (AssetProxyWebViewClient), so the web build no longer contains them. The
# rm below is a safeguard for stale checkouts. Requires config.json to set
# "assetsBaseUrl" (pass it via CONFIG_JSON) to the asset-storage origin so
# the app knows where to fetch /migration_exports/... etc. from; keep
# "assetStorageBaseUrl" empty for mobile so paths stay origin-relative and
# hit the native proxy.
echo "==> Removing streamed assets (migration_exports) from bundle"
rm -rf "$MOBILE_DIR/www/migration_exports"

echo "==> Done. www/ now contains the compiled web client (minus streamed assets)."
