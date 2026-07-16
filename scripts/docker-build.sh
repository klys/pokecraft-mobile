#!/usr/bin/env bash
#
# Builds the PokeCraft Android debug APK entirely in Docker (no local Android
# SDK required) and drops it in ./build/pokecraft-debug.apk.
#
# By default the APK is configured to talk to the dev server on THIS computer's
# LAN IP (http://<LAN-IP>:3001), so a phone on the same Wi-Fi can connect to the
# `docker compose up` stack.
#
# Environment overrides:
#   HOST_IP        LAN IP to bake into the app. Default: this machine's primary IP.
#   BACKEND_PORT   server-poke.io port. Default: 3001.
#   BACKEND_URL    Full backend URL. Overrides HOST_IP/BACKEND_PORT if set.
#   ASSET_STORAGE_PORT       asset-storage port. Default: 8090.
#   ASSET_STORAGE_BASE_URL   Full asset-storage URL. Overrides HOST_IP/ASSET_STORAGE_PORT if set.
#   WEB_SRC        Path to the client-poke.io checkout. Default: ../client-poke.io
#
set -euo pipefail

MOBILE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

load_env_file() {
  local env_file="$MOBILE_DIR/.env"
  local line key value

  [ -f "$env_file" ] || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -z "$line" ] && continue
    [[ "$line" == \#* ]] && continue
    [[ "$line" == export\ * ]] && line="${line#export }"
    [[ "$line" == *=* ]] || continue

    key="${line%%=*}"
    value="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"

    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    [ -z "${!key+x}" ] || continue

    if [[ "$value" == \"*\" && "$value" == *\" ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
      value="${value:1:${#value}-2}"
    fi

    export "$key=$value"
  done < "$env_file"
}

load_env_file

DOCKERFILE="$MOBILE_DIR/docker/Dockerfile"
OUT_DIR="$MOBILE_DIR/build"
WEB_SRC="${WEB_SRC:-$MOBILE_DIR/../client-poke.io}"

if ! command -v docker >/dev/null 2>&1; then
  echo "error: docker is not installed or not on PATH." >&2
  exit 1
fi
if [ ! -d "$WEB_SRC" ]; then
  echo "error: web source not found at '$WEB_SRC' (set WEB_SRC)." >&2
  exit 1
fi
WEB_SRC="$(cd "$WEB_SRC" && pwd)"

# Resolve the backend (Socket.IO) and asset-storage URLs the app points at.
# Game assets (/migration_exports, /map-assets, sprites) are streamed from
# ASSET_STORAGE_BASE_URL — the standalone asset-storage nginx server
# (:8090 in the dev stack, see ../asset-storage).
BACKEND_PORT="${BACKEND_PORT:-3001}"
ASSET_STORAGE_PORT="${ASSET_STORAGE_PORT:-8090}"
if [ -z "${BACKEND_URL:-}" ] || [ -z "${ASSET_STORAGE_BASE_URL:-}" ]; then
  HOST_IP="${HOST_IP:-$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[0-9.]+' | head -1)}"
  if [ -z "${HOST_IP:-}" ]; then
    HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  if [ -z "${HOST_IP:-}" ]; then
    echo "error: could not detect this machine's LAN IP. Set HOST_IP (or BACKEND_URL + ASSET_STORAGE_BASE_URL)." >&2
    exit 1
  fi
fi
BACKEND_URL="${BACKEND_URL:-http://${HOST_IP}:${BACKEND_PORT}}"
ASSET_STORAGE_BASE_URL="${ASSET_STORAGE_BASE_URL:-http://${HOST_IP}:${ASSET_STORAGE_PORT}}"

# The APK bundles the asset-storage media and the shared data snapshots so
# the app plays from its local cache (the remote hosts serve only content
# newer than the bundle).
ASSETS_SRC="${ASSETS_SRC:-$MOBILE_DIR/../asset-storage/assets}"
BUNDLED_DATA_DIR="${BUNDLED_DATA_DIR:-$MOBILE_DIR/bundled-data}"

if [ ! -d "$ASSETS_SRC" ]; then
  echo "error: asset-storage assets not found at '$ASSETS_SRC' (set ASSETS_SRC)." >&2
  exit 1
fi
if [ ! -d "$BUNDLED_DATA_DIR" ] || [ ! -f "$BUNDLED_DATA_DIR/playable-maps.json" ]; then
  echo "error: bundled data not found at '$BUNDLED_DATA_DIR'." >&2
  echo "       Generate it with ../server-poke.io/tools/export-bundled-data.sh \"$BUNDLED_DATA_DIR\"" >&2
  echo "       (needs a running server-poke.io; set SERVER_URL to point at it)." >&2
  exit 1
fi
ASSETS_SRC="$(cd "$ASSETS_SRC" && pwd)"
BUNDLED_DATA_DIR="$(cd "$BUNDLED_DATA_DIR" && pwd)"

echo "==> Web source  : $WEB_SRC"
echo "==> Backend URL : $BACKEND_URL"
echo "==> Asset URL   : $ASSET_STORAGE_BASE_URL   (fallback for content newer than the bundle)"
echo "==> Bundled media: $ASSETS_SRC ($(du -sh "$ASSETS_SRC" | cut -f1))"
echo "==> Bundled data : $BUNDLED_DATA_DIR ($(du -sh "$BUNDLED_DATA_DIR" | cut -f1))"
echo "==> Output dir  : $OUT_DIR"
echo

mkdir -p "$OUT_DIR"

DOCKER_BUILDKIT=1 docker buildx build \
  --build-context "web=$WEB_SRC" \
  --build-context "assets=$ASSETS_SRC" \
  --build-context "bundleddata=$BUNDLED_DATA_DIR" \
  --build-arg "BACKEND_URL=$BACKEND_URL" \
  --build-arg "ASSET_STORAGE_BASE_URL=$ASSET_STORAGE_BASE_URL" \
  --target export \
  --output "type=local,dest=$OUT_DIR" \
  -f "$DOCKERFILE" \
  "$MOBILE_DIR"

echo
echo "==> APK ready: $OUT_DIR/pokecraft-debug.apk"
echo
echo "Install it on a phone connected via USB (adb):"
echo "    adb install -r \"$OUT_DIR/pokecraft-debug.apk\""
echo
echo "For the app to reach this computer, make sure:"
echo "  1. The dev stack is up:  docker compose up -d"
echo "       - server-poke.io (Socket.IO) on :$BACKEND_PORT   -> $BACKEND_URL"
echo "       - asset-storage (nginx, serves game assets) on :$ASSET_STORAGE_PORT -> $ASSET_STORAGE_BASE_URL"
echo "  2. The phone is on the SAME Wi-Fi / LAN as this computer."
echo "  3. This computer's firewall allows inbound TCP $BACKEND_PORT and $ASSET_STORAGE_PORT."
echo "  4. The server allows the app origin 'https://localhost' in CLIENT_ORIGIN"
echo "     (already added to server-poke.io/index.ts defaults)."
