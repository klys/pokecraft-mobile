# syntax=docker/dockerfile:1
#
# Builds the PokeCraft Android APK end-to-end in Docker (no local Android SDK
# needed). Driven by scripts/docker-build.sh, which supplies:
#   - primary build context  = client-mobile/           (this folder)
#   - named build context    = web         -> ../client-poke.io
#   - named build context    = assets      -> ../asset-storage/assets
#   - named build context    = bundleddata -> ./bundled-data (export-bundled-data.sh output)
#   - --build-arg BACKEND_URL = http://<LAN-IP>:3001
#   - --build-arg ASSET_STORAGE_BASE_URL = http://<LAN-IP>:8090
#
# The APK ships the full asset-storage media plus the shared data snapshots
# (playable maps + public designer sections) inside www/, so the app plays
# from its local cache; the remote asset host and the realtime server are only
# used for content that is newer than the bundle (AssetProxyWebViewClient
# serves bundled paths locally and proxies only misses).
#
# Output: a debug APK, exported to ./build/ by the wrapper script.

# ---- 1. Build the web client (client-poke.io) -------------------------------
FROM node:22-bookworm AS webbuild
WORKDIR /web
# `web` is a named build context pointing at the client-poke.io checkout.
COPY --from=web package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci
COPY --from=web . .
ARG BACKEND_URL=""
# Origin of the asset-storage nginx server (see ../asset-storage). Written to
# `assetsBaseUrl`, the native proxy's upstream. `assetStorageBaseUrl` is
# deliberately pinned empty in mobile builds so the web code keeps asset paths
# origin-relative and AssetProxyWebViewClient intercepts them (no
# mixed-content/CORS in the WebView).
ARG ASSET_STORAGE_BASE_URL=""
RUN if [ -z "$BACKEND_URL" ] || [ -z "$ASSET_STORAGE_BASE_URL" ]; then \
      echo "error: BACKEND_URL and ASSET_STORAGE_BASE_URL build args are required for mobile builds." >&2 ; \
      exit 1 ; \
    fi ; \
    node -e 'const fs=require("fs"); const [backendUrl, assetsBaseUrl]=process.argv.slice(1); fs.writeFileSync("public/config.json", JSON.stringify({ backendUrl, assetsBaseUrl, assetStorageBaseUrl: "" }, null, 2) + "\n");' "$BACKEND_URL" "$ASSET_STORAGE_BASE_URL" ; \
    echo "web build -> backend '$BACKEND_URL', asset storage '$ASSET_STORAGE_BASE_URL'"
RUN npm run build
# Drop any stale copy from the web checkout; the authoritative media comes
# from the `assets` build context and is layered into www/ below.
RUN rm -rf build/migration_exports

# ---- 2. Build the Android APK -----------------------------------------------
FROM eclipse-temurin:21-jdk-jammy AS androidbuild
ENV DEBIAN_FRONTEND=noninteractive
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV ANDROID_HOME=/opt/android-sdk
ENV PATH="${PATH}:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools"

# Node (for `npm ci` + Capacitor CLI) plus tooling.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl unzip ca-certificates git \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Android command-line tools + the SDK packages this project targets.
ARG ANDROID_CMDLINE_VERSION=11076708
ARG ANDROID_PLATFORM=android-36
ARG ANDROID_BUILD_TOOLS=36.0.0
RUN mkdir -p ${ANDROID_SDK_ROOT}/cmdline-tools \
    && curl -fsSL -o /tmp/cmdline-tools.zip \
       https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_VERSION}_latest.zip \
    && unzip -q /tmp/cmdline-tools.zip -d ${ANDROID_SDK_ROOT}/cmdline-tools \
    && mv ${ANDROID_SDK_ROOT}/cmdline-tools/cmdline-tools ${ANDROID_SDK_ROOT}/cmdline-tools/latest \
    && rm /tmp/cmdline-tools.zip \
    && yes | sdkmanager --licenses >/dev/null \
    && sdkmanager "platform-tools" "platforms;${ANDROID_PLATFORM}" "build-tools;${ANDROID_BUILD_TOOLS}" >/dev/null

WORKDIR /mobile
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci
COPY . .
# Replace the placeholder www/ with the compiled web client from stage 1.
RUN rm -rf www
COPY --from=webbuild /web/build ./www
# Bundle the asset-storage media (same layout nginx serves at /) and the
# shared data snapshots into the app. Capacitor serves www/ from the app
# origin, so /migration_exports/..., /map-assets/... and
# /bundled-data/... resolve locally without touching the network.
COPY --from=assets . ./www/
COPY --from=bundleddata . ./www/bundled-data/

RUN npx cap sync android
RUN --mount=type=cache,target=/root/.gradle \
    cd android && chmod +x gradlew && ./gradlew assembleDebug --no-daemon --stacktrace

# ---- 3. Export just the APK --------------------------------------------------
FROM scratch AS export
COPY --from=androidbuild /mobile/android/app/build/outputs/apk/debug/app-debug.apk /pokecraft-debug.apk
