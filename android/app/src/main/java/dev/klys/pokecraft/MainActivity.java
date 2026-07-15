package dev.klys.pokecraft;

import android.os.Bundle;
import android.view.WindowManager;

import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.core.view.WindowInsetsControllerCompat;

import com.getcapacitor.BridgeActivity;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

public class MainActivity extends BridgeActivity {

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Keep the display awake while playing (controllers don't touch the screen).
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        // Immersive, edge-to-edge fullscreen so the game canvas owns the display.
        enableImmersiveMode();

        // Game assets (/migration_exports/..., /map-assets/..., sprites) are
        // not bundled to keep the APK small; stream them from the standalone
        // asset-storage nginx server instead.
        String assetHost = readAssetHost();
        if (!assetHost.isEmpty()) {
            getBridge().setWebViewClient(new AssetProxyWebViewClient(getBridge(), assetHost));
        }
    }

    /**
     * Reads the asset-storage origin the native proxy streams from, from the
     * bundled config.json (written at build time). `assetsBaseUrl` is the
     * proxy upstream; the web-level `assetStorageBaseUrl` key must stay empty
     * in mobile builds so asset paths remain origin-relative and get
     * intercepted by AssetProxyWebViewClient.
     */
    private String readAssetHost() {
        try (InputStream is = getAssets().open("public/config.json")) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] chunk = new byte[4096];
            int read;
            while ((read = is.read(chunk)) != -1) {
                out.write(chunk, 0, read);
            }
            JSONObject config = new JSONObject(new String(out.toByteArray(), StandardCharsets.UTF_8));
            return config.optString("assetsBaseUrl", "");
        } catch (Exception e) {
            return "";
        }
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) {
            // Re-hide the system bars after dialogs, notifications or app switches.
            enableImmersiveMode();
        }
    }

    private void enableImmersiveMode() {
        WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
        WindowInsetsControllerCompat controller =
                WindowCompat.getInsetsController(getWindow(), getWindow().getDecorView());
        if (controller != null) {
            controller.hide(WindowInsetsCompat.Type.systemBars());
            controller.setSystemBarsBehavior(
                    WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
        }
    }
}
