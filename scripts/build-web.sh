#!/usr/bin/env bash
#
# Builds the PokeCraft web client (client-poke.io) and copies the production
# bundle into ./www so Capacitor can wrap it.
#
# Environment variables:
#   WEB_SRC                  Path to the client-poke.io checkout. Default: ../client-poke.io
#   CONFIG_JSON              Optional. If set, its contents replace public/config.json
#                            before the build (used by CI to inject mobile config).
#   BACKEND_URL              Socket.IO server URL. Used when CONFIG_JSON is unset.
#   ASSET_STORAGE_BASE_URL   Asset-storage origin. Used when CONFIG_JSON is unset.
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

write_mobile_config() {
  local output_file="$1"

  if [ -n "${CONFIG_JSON:-}" ]; then
    echo "==> Writing mobile public/config.json from \$CONFIG_JSON"
    node - "$output_file" <<'NODE'
const fs = require('fs');
const [outputFile] = process.argv.slice(2);
const raw = process.env.CONFIG_JSON || '';

function stripQuotes(value) {
  const trimmed = value.trim();
  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    return trimmed.slice(1, -1);
  }
  return trimmed;
}

function parseDotenv(text) {
  const parsed = {};

  for (let line of text.split(/\r?\n/)) {
    line = line.trim();
    if (!line || line.startsWith('#')) {
      continue;
    }
    if (line.startsWith('export ')) {
      line = line.slice('export '.length).trim();
    }

    const index = line.indexOf('=');
    if (index === -1) {
      continue;
    }

    const key = line.slice(0, index).trim();
    const value = stripQuotes(line.slice(index + 1));
    if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) {
      parsed[key] = value;
    }
  }

  return parsed;
}

function normalizeConfig(input) {
  const backendUrl = input.backendUrl || input.BACKEND_URL || input.MOBILE_BACKEND_URL || '';
  const assetsBaseUrl =
    input.assetsBaseUrl ||
    input.ASSETS_BASE_URL ||
    input.ASSET_STORAGE_BASE_URL ||
    input.MOBILE_ASSET_STORAGE_BASE_URL ||
    '';

  return {
    backendUrl,
    assetsBaseUrl,
    assetStorageBaseUrl: ''
  };
}

let input;

try {
  input = JSON.parse(raw);
  if (!input || Array.isArray(input) || typeof input !== 'object') {
    throw new Error('CONFIG_JSON must be an object');
  }
} catch (jsonError) {
  input = parseDotenv(raw);
  if (Object.keys(input).length === 0) {
    console.error('error: CONFIG_JSON must be either a JSON object or dotenv-style KEY=value lines.');
    console.error('Expected backendUrl/assetsBaseUrl JSON keys, or BACKEND_URL/ASSET_STORAGE_BASE_URL lines.');
    process.exit(1);
  }
}

fs.writeFileSync(outputFile, JSON.stringify(normalizeConfig(input), null, 2) + '\n');
NODE
    return 0
  fi

  if [ -n "${BACKEND_URL:-}" ] || [ -n "${ASSET_STORAGE_BASE_URL:-}" ]; then
    if [ -z "${BACKEND_URL:-}" ] || [ -z "${ASSET_STORAGE_BASE_URL:-}" ]; then
      echo "error: set both BACKEND_URL and ASSET_STORAGE_BASE_URL, or set CONFIG_JSON." >&2
      exit 1
    fi

    echo "==> Writing mobile public/config.json from BACKEND_URL + ASSET_STORAGE_BASE_URL"
    node -e 'const fs=require("fs"); const [backendUrl, assetsBaseUrl, out]=process.argv.slice(1); fs.writeFileSync(out, JSON.stringify({ backendUrl, assetsBaseUrl, assetStorageBaseUrl: "" }, null, 2) + "\n");' \
      "$BACKEND_URL" "$ASSET_STORAGE_BASE_URL" "$output_file"
    return 0
  fi

  echo "error: no mobile config provided." >&2
  echo "       Set MOBILE_CONFIG_JSON, or set MOBILE_BACKEND_URL + MOBILE_ASSET_STORAGE_BASE_URL." >&2
  echo "       Local builds can also use BACKEND_URL + ASSET_STORAGE_BASE_URL in client-mobile/.env." >&2
  exit 1
}

validate_mobile_config() {
  local config_file="$1"

  node - "$config_file" <<'NODE'
const fs = require('fs');
const [configFile] = process.argv.slice(2);
let config;

try {
  config = JSON.parse(fs.readFileSync(configFile, 'utf8'));
} catch (error) {
  console.error(`error: ${configFile} must be valid JSON.`);
  process.exit(1);
}

const problems = [];
if (!config.backendUrl || typeof config.backendUrl !== 'string') {
  problems.push('backendUrl must be set to the Socket.IO server URL');
}
if (!config.assetsBaseUrl || typeof config.assetsBaseUrl !== 'string') {
  problems.push('assetsBaseUrl must be set to the asset-storage origin for the native proxy');
}
if (config.assetStorageBaseUrl) {
  problems.push('assetStorageBaseUrl must be empty for mobile builds so the native asset proxy can intercept root-relative paths');
}

if (problems.length) {
  console.error(`error: ${configFile} is not valid for a mobile build:`);
  for (const problem of problems) {
    console.error(`  - ${problem}`);
  }
  console.error('Set CONFIG_JSON, or set BACKEND_URL + ASSET_STORAGE_BASE_URL (the local .env file is loaded automatically).');
  process.exit(1);
}
NODE
}

load_env_file

WEB_SRC="${WEB_SRC:-$MOBILE_DIR/../client-poke.io}"

if [ ! -d "$WEB_SRC" ]; then
  echo "error: web source not found at '$WEB_SRC'." >&2
  echo "       set WEB_SRC to your client-poke.io checkout." >&2
  exit 1
fi

WEB_SRC="$(cd "$WEB_SRC" && pwd)"
echo "==> Building web client from: $WEB_SRC"

pushd "$WEB_SRC" >/dev/null

write_mobile_config public/config.json
validate_mobile_config public/config.json

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
