import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'dev.klys.pokecraft',
  appName: 'PokeCraft',
  // The web build is produced from ../client-poke.io and copied here by
  // scripts/build-web.sh. See README.md.
  webDir: 'www',
  android: {
    // The WebView runs on the secure `https://localhost` scheme. Allowing mixed
    // content lets it reach a plain-HTTP backend (e.g. http://<LAN-IP>:3001 when
    // testing against the local dev stack). The release backend is HTTPS, so no
    // mixed content actually occurs there. Cleartext itself is additionally
    // gated to debug builds via android/app/src/debug/ (see that manifest).
    allowMixedContent: true,
  },
  server: {
    androidScheme: 'https',
  },
  plugins: {
    SplashScreen: {
      launchShowDuration: 800,
      backgroundColor: '#000000',
      showSpinner: false,
    },
  },
};

export default config;
