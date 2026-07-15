# syntax=docker/dockerfile:1
#
# Builds the PokeCraft Android APK end-to-end in Docker (no local Android SDK
# needed). Driven by scripts/docker-build.sh, which supplies:
#   - primary build context  = client-mobile/           (this folder)
#   - named build context    = web  -> ../client-poke.io
#   - --build-arg BACKEND_URL = http://<LAN-IP>:3001    (optional)
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
RUN if [ -n "$BACKEND_URL" ] || [ -n "$ASSET_STORAGE_BASE_URL" ]; then \
      printf '{"backendUrl":"%s","assetsBaseUrl":"%s","assetStorageBaseUrl":""}' "$BACKEND_URL" "$ASSET_STORAGE_BASE_URL" > public/config.json ; \
      echo "web build -> backend '$BACKEND_URL', asset storage '$ASSET_STORAGE_BASE_URL'" ; \
    else \
      echo "web build -> using client default backend" ; \
    fi
RUN npm run build
# Heavy assets are streamed from the host at runtime (see AssetProxyWebViewClient),
# so drop them from the bundle to keep the APK small (~300MB -> ~11MB).
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

RUN npx cap sync android
RUN --mount=type=cache,target=/root/.gradle \
    cd android && chmod +x gradlew && ./gradlew assembleDebug --no-daemon --stacktrace

# ---- 3. Export just the APK --------------------------------------------------
FROM scratch AS export
COPY --from=androidbuild /mobile/android/app/build/outputs/apk/debug/app-debug.apk /pokecraft-debug.apk
