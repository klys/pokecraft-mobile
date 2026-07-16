package dev.klys.pokecraft;

import android.content.res.AssetManager;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;

import com.getcapacitor.Bridge;
import com.getcapacitor.BridgeWebViewClient;

import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Serves heavy game assets local-first: builds that bundle the asset-storage
 * media inside the APK (under www/, i.e. APK assets "public/...") answer
 * asset requests from the bundle via Capacitor's normal local handling; only
 * paths missing from the bundle (e.g. content added after the app shipped)
 * are streamed from the remote `assetHost` and returned transparently.
 * Because remote bytes come back on the app's own origin, all existing
 * <img>/<audio>/fetch references keep working with no web-side changes, and
 * there is no CORS/mixed-content concern.
 *
 * Everything else falls through to Capacitor's normal asset handling.
 */
public class AssetProxyWebViewClient extends BridgeWebViewClient {

    // Everything the asset-storage nginx server hosts. The bundled config.json
    // keeps assetStorageBaseUrl empty so the web code emits these paths
    // origin-relative and they land here instead of triggering
    // cross-origin/mixed-content fetches from the WebView.
    private static final String[] PROXIED_PREFIXES = {
            "/migration_exports/",
            "/map-assets/",
            "/character0/",
            "/map0/",
            "/objects/"
    };

    private static final String[] PROXIED_FILES = {
            "/missile0.gif",
            "/bg0.jpg",
            "/ship.png",
            "/explosion0.png",
            "/explosion1.svg"
    };

    private final String assetHost; // e.g. "http://192.168.1.10:8090" (no trailing slash)
    private final AssetManager assetManager;
    // Bundled-presence lookups hit AssetManager.open(); memoize per path so
    // repeated references (tiles, frames) don't re-probe the APK.
    private final Map<String, Boolean> bundledPathCache = new ConcurrentHashMap<>();

    public AssetProxyWebViewClient(Bridge bridge, String assetHost) {
        super(bridge);
        this.assetHost = assetHost == null ? "" : assetHost.replaceAll("/+$", "");
        this.assetManager = bridge.getContext().getAssets();
    }

    @Override
    public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
        WebResourceResponse proxied = tryProxy(request);
        if (proxied != null) {
            return proxied;
        }
        return super.shouldInterceptRequest(view, request);
    }

    /**
     * True when the path exists inside the APK bundle (Capacitor packages
     * www/ as APK assets under "public/"). Bundled files are served by the
     * default local handler instead of the remote proxy.
     */
    private boolean isBundled(String path) {
        Boolean cached = bundledPathCache.get(path);
        if (cached != null) {
            return cached;
        }

        boolean exists;
        try (InputStream ignored = assetManager.open("public" + path)) {
            exists = true;
        } catch (Exception e) {
            exists = false;
        }

        bundledPathCache.put(path, exists);
        return exists;
    }

    private static boolean isProxiedPath(String path) {
        for (String prefix : PROXIED_PREFIXES) {
            if (path.startsWith(prefix)) {
                return true;
            }
        }
        for (String file : PROXIED_FILES) {
            if (path.equals(file)) {
                return true;
            }
        }
        return false;
    }

    private WebResourceResponse tryProxy(WebResourceRequest request) {
        if (assetHost.isEmpty() || request == null || request.getUrl() == null) {
            return null;
        }
        if (!"GET".equalsIgnoreCase(request.getMethod())) {
            return null;
        }
        String path = request.getUrl().getPath();
        if (path == null || !isProxiedPath(path)) {
            return null;
        }
        if (isBundled(path)) {
            // Present in the APK bundle: let Capacitor's local server serve it.
            return null;
        }

        try {
            String query = request.getUrl().getQuery();
            String target = assetHost + path + (query != null ? "?" + query : "");

            HttpURLConnection conn = (HttpURLConnection) new URL(target).openConnection();
            conn.setInstanceFollowRedirects(true);
            conn.setConnectTimeout(15000);
            conn.setReadTimeout(30000);

            // Forward the Range header so audio/video seeking works.
            Map<String, String> reqHeaders = request.getRequestHeaders();
            if (reqHeaders != null && reqHeaders.get("Range") != null) {
                conn.setRequestProperty("Range", reqHeaders.get("Range"));
            }
            conn.connect();

            int status = conn.getResponseCode();
            String contentType = conn.getContentType();
            String mime = contentType;
            String encoding = null;
            if (contentType != null && contentType.contains(";")) {
                String[] parts = contentType.split(";");
                mime = parts[0].trim();
                for (int i = 1; i < parts.length; i++) {
                    String seg = parts[i].trim().toLowerCase(Locale.ROOT);
                    if (seg.startsWith("charset=")) {
                        encoding = seg.substring("charset=".length());
                    }
                }
            }
            if (mime == null || mime.isEmpty()) {
                mime = guessMime(path);
            }

            InputStream body = status >= 400 ? conn.getErrorStream() : conn.getInputStream();

            Map<String, String> respHeaders = new HashMap<>();
            for (Map.Entry<String, List<String>> entry : conn.getHeaderFields().entrySet()) {
                if (entry.getKey() != null && entry.getValue() != null && !entry.getValue().isEmpty()) {
                    respHeaders.put(entry.getKey(), entry.getValue().get(0));
                }
            }

            String reason = conn.getResponseMessage();
            if (reason == null || reason.isEmpty()) {
                reason = status >= 400 ? "Error" : "OK";
            }

            return new WebResourceResponse(mime, encoding, status, reason, respHeaders, body);
        } catch (Exception e) {
            // On any failure fall back to default handling (which will 404, matching web behaviour).
            return null;
        }
    }

    private static String guessMime(String path) {
        String lower = path.toLowerCase(Locale.ROOT);
        if (lower.endsWith(".png")) return "image/png";
        if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) return "image/jpeg";
        if (lower.endsWith(".gif")) return "image/gif";
        if (lower.endsWith(".webp")) return "image/webp";
        if (lower.endsWith(".svg")) return "image/svg+xml";
        if (lower.endsWith(".json")) return "application/json";
        if (lower.endsWith(".mp3")) return "audio/mpeg";
        if (lower.endsWith(".ogg")) return "audio/ogg";
        if (lower.endsWith(".wav")) return "audio/wav";
        if (lower.endsWith(".mid") || lower.endsWith(".midi")) return "audio/midi";
        if (lower.endsWith(".m4a")) return "audio/mp4";
        return "application/octet-stream";
    }
}
