# PokeCraft Mobile (Android)

Capacitor wrapper that packages the PokeCraft web client
([client-poke.io](https://github.com/klys/client-poke.io)) as a native Android
app, with physical **gamepad support** and immersive landscape fullscreen.

- **appId:** `dev.klys.pokecraft`
- **appName:** PokeCraft
- **Capacitor:** 8.x · **minSdk:** 24 (Android 7) · **target/compileSdk:** 36

The web client uses `createHashRouter`, so its routing works unchanged inside
the WebView (no server needed). At runtime it fetches `/config.json` for the
backend URL and falls back to its built-in default backend if that's absent.

## How it fits together

```
client-poke.io/        # the React (CRA) game — separate repo, the source of truth
client-mobile/         # THIS repo — the Capacitor Android shell
  capacitor.config.ts
  scripts/build-web.sh # builds client-poke.io and copies its bundle into www/
  www/                 # generated web bundle (gitignored)
  android/             # native Android project (committed)
  webapp-integration/
    gamepad.ts         # drop-in Web Gamepad helper for the React app
  .github/workflows/android.yml
```

`build-web.sh` builds the React app and copies its `build/` output into `www/`;
`cap sync` then copies `www/` into the Android project.

## Prerequisites

- Node 22, JDK 21
- Android SDK (platform 36, build-tools 36) — Android Studio installs these.
  Set `ANDROID_HOME` / `ANDROID_SDK_ROOT`.
- A checkout of `client-poke.io` next to this folder (or point `WEB_SRC` at it).

## Local development

```bash
npm install

# Build the web client (../client-poke.io by default) into www/ and sync it:
npm run prepare:android          # = build:web + cap sync

# Open in Android Studio to run on a device/emulator:
npm run open:android

# ...or build a debug APK from the CLI:
npm run apk:debug                # -> android/app/build/outputs/apk/debug/app-debug.apk
```

Point at a web checkout elsewhere, or override the backend URL:

```bash
WEB_SRC=/path/to/client-poke.io \
CONFIG_JSON='{"backendUrl":"https://pokecraft-staging-0.klys.dev","assetsBaseUrl":"https://assets.pokecraft.klys.dev","assetStorageBaseUrl":""}' \
npm run build:web
```

`scripts/build-web.sh` and `scripts/docker-build.sh` also load `client-mobile/.env`
automatically. Values exported in your shell still win over `.env`.

## Gamepad support

The Android System WebView exposes the standard **Web Gamepad API**, so the same
code powers web and Android. Native side is already configured:

- The app installs on controller-first devices (touchscreen not required) and
  advertises `android.hardware.gamepad` (not required).
- Immersive landscape fullscreen; the screen is kept awake while playing.

To consume controllers in the game, copy
[`webapp-integration/gamepad.ts`](webapp-integration/gamepad.ts) into the
client-poke.io app (e.g. `src/input/gamepad.ts`) and poll it from the game loop —
see the header comment in that file for a usage example and the standard button
map. No native plugin is required.

> Note: on most controllers the **B** button maps to Android's BACK key. If that
> interferes with gameplay, intercept it on the web side
> (`@capacitor/app`'s `backButton` listener) or handle it in `MainActivity`.

## On-screen touch controls

Physical controllers aren't always around, so the app also shows an on-screen
gamepad. Because this is a **shared cross-platform codebase**, the overlay lives
in the web app (`client-poke.io`) and renders **only under Capacitor** — never in
the browser or Electron builds. Files (in the client-poke.io repo):

- `src/platform.ts` — `isCapacitor()` / `getPlatform()` runtime detection
- `src/components/game/VirtualControls.tsx` + `.css` — the overlay
- mounted in `src/components/game/Game.tsx`

Layout and key mapping (buttons dispatch synthetic `KeyboardEvent`s the game
already listens for):

| Control | Position | Sends |
| --- | --- | --- |
| D-pad | bottom-left | `ArrowUp` / `ArrowDown` / `ArrowLeft` / `ArrowRight` (auto-repeat while held) |
| A | bottom-right | `Enter` |
| B | bottom-right | `Escape` |
| X | bottom-right | `Space` |
| Y | bottom-right | `m` (open menu — wire your menu UI to the `m` key) |

Text input: when an `<input>`/`<textarea>` is focused the WebView shows the
native soft keyboard automatically, and the overlay auto-hides so it never
covers the field — no extra plugin needed.

**Physical gamepad takes over:** when a controller is connected the on-screen
buttons disappear (you're using the Web Gamepad API instead); unplug the
controller and they reappear.

## Build with Docker (no local Android SDK) + test against the local server

`scripts/docker-build.sh` builds a debug APK entirely inside Docker and writes it
to `build/pokecraft-debug.apk` (the `build/` folder is gitignored). It requires
only Docker (with BuildKit/buildx) — no JDK or Android SDK on the host.

By default the APK is pointed at **this computer's LAN IP** on port 3001, so a
phone on the same Wi-Fi can talk to your `docker compose up` dev stack:

```bash
# 1. Bring up the server stack (postgres, redis, server-poke.io:3001, ...)
cd /home/klys/Dev/pokecraft && docker compose up -d

# 2. Build the APK (auto-detects your LAN IP -> http://<LAN-IP>:3001)
cd client-mobile && ./scripts/docker-build.sh

# 3. Install on a USB-connected phone
adb install -r build/pokecraft-debug.apk
```

Override the target backend if auto-detection isn't what you want:

```bash
HOST_IP=192.168.1.50 ./scripts/docker-build.sh          # different IP
BACKEND_PORT=3002 ./scripts/docker-build.sh             # different port
BACKEND_URL=https://pokecraft-staging-0.klys.dev \
ASSET_STORAGE_BASE_URL=https://assets.pokecraft.klys.dev \
./scripts/docker-build.sh
```

For the phone to actually reach your machine, all of these must hold:

- The phone and this computer are on the **same LAN/Wi-Fi**.
- The host **firewall allows inbound TCP 3001** (the published server port).
- The server accepts the app's WebView origin. The Capacitor app runs on
  `https://localhost`, which is already in `server-poke.io`'s default
  `CLIENT_ORIGIN` allow-list (alongside `capacitor://localhost`).
- HTTP works because debug APKs permit cleartext
  (`android/app/src/debug/…/network_security_config.xml`) and the WebView allows
  mixed content. Release builds keep cleartext blocked.

## Asset streaming (small APK)

The game content (`migration_exports/` battle GIFs, BGM/audio, event pictures,
pokémon animations, plus `map-assets/`, `character0/` and the other sprites —
~360 MB) lives in the standalone `../asset-storage` nginx server and is **not
bundled** in the APK (~11 MB instead of ~300 MB).

At runtime a native WebView proxy
([`AssetProxyWebViewClient.java`](android/app/src/main/java/dev/klys/pokecraft/AssetProxyWebViewClient.java),
installed in `MainActivity`) intercepts requests the WebView makes to
`https://localhost/migration_exports/...` (and the other asset prefixes) and
streams them from `assetsBaseUrl` (from `config.json`). Because the bytes come
back on the app's own origin, every existing `<img>`/`<audio>`/`fetch`
reference works unchanged, with no CORS or mixed-content issues. The WebView
caches responses, so repeat loads are fast; there is no separate first-launch
download step.

Two config keys matter in the bundled `config.json`:

- `assetsBaseUrl` — the native proxy's upstream; must point at the
  asset-storage server.
- `assetStorageBaseUrl` — the web-level asset origin used by browser builds;
  **keep it empty in mobile builds** so asset paths stay origin-relative and
  get intercepted by the proxy.

Where `assetsBaseUrl` should point:

- **Dev:** the `asset-storage` nginx service from the root compose stack
  (`http://<LAN-IP>:8090`). `docker-build.sh` sets this automatically
  (override with `ASSET_STORAGE_BASE_URL` / `ASSET_STORAGE_PORT`).
- **Prod / CI:** your deployed asset-storage host. Put it in the
  `MOBILE_CONFIG_JSON` secret.

If `assetsBaseUrl` is empty the proxy is disabled and those paths 404 — so it
must be set for every mobile build.

## CI (GitHub Actions)

[`.github/workflows/android.yml`](.github/workflows/android.yml) checks out this
repo **and** `klys/client-poke.io`, builds the web bundle, runs `cap sync`, and
produces a **debug APK**. Pull requests upload it as a build artifact
(`pokecraft-debug-apk`); pushes to `main`/`master` and **Run workflow** builds
also publish a GitHub prerelease with that APK attached.

Optional repository secrets:
You can either set `MOBILE_CONFIG_JSON` directly, or set the backend and asset
storage URLs separately as repository secrets or variables.

| Secret | Purpose |
| --- | --- |
| `MOBILE_CONFIG_JSON` | Contents of `config.json`, either as JSON or dotenv-style lines. Should set `backendUrl` / `BACKEND_URL` and `assetsBaseUrl` / `ASSET_STORAGE_BASE_URL`, and keep `assetStorageBaseUrl` empty, e.g. `{"backendUrl":"https://…","assetsBaseUrl":"https://assets.pokecraft.klys.dev","assetStorageBaseUrl":""}` or two lines: `BACKEND_URL=https://…` and `ASSET_STORAGE_BASE_URL=https://assets.pokecraft.klys.dev`. Required because mobile builds don't bundle the assets. |
| `MOBILE_BACKEND_URL` / `BACKEND_URL` | Socket.IO server URL. Used only when `MOBILE_CONFIG_JSON` is not set. Can be a repository secret or variable. |
| `MOBILE_ASSET_STORAGE_BASE_URL` / `ASSET_STORAGE_BASE_URL` | Asset-storage origin. Used only when `MOBILE_CONFIG_JSON` is not set. Can be a repository secret or variable. |
| `WEB_REPO_TOKEN` | PAT to read `client-poke.io` if you make it **private**. Not needed while it's public. |

### Store release / signing (later)

The current CI release is still an unsigned-for-store **debug** APK
(debug-keystore signed, installable for testing). To ship to Play, add a release
keystore + secrets and a `assembleRelease` step — intentionally left out for now.
