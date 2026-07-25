package app.gullify.gullify

import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.PowerManager
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Verrous réseau tenus pendant la lecture. just_audio (0.10) ne pose
        // aucun WAKE_MODE sur ExoPlayer : écran éteint, la radio Wi-Fi passe en
        // power-save et le flux cale en pleine chanson (« mise en tampon ») pour
        // ne repartir qu'au réveil. Un WifiLock HIGH_PERF + un WakeLock partiel
        // (CPU) reproduisent WAKE_MODE_NETWORK et gardent le flux vivant en
        // veille. Verrous statiques + applicationContext : ils survivent à la
        // recréation de l'activité et meurent avec le process (aucune fuite si
        // Android tue l'app). Acquis sur ▶, relâchés sur ⏸/stop côté Dart.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "gullify/netlock",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquire" -> { setNetworkLock(applicationContext, true); result.success(true) }
                "release" -> { setNetworkLock(applicationContext, false); result.success(true) }
                else -> result.notImplemented()
            }
        }
        // Installeur d'APK maison : lance l'intent système sur le fichier
        // téléchargé (remplace open_filex, non enregistré sur certains
        // appareils → MissingPluginException).
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "gullify/installer",
        ).setMethodCallHandler { call, result ->
            if (call.method == "installApk") {
                try {
                    val path = call.argument<String>("path")!!
                    val uri = FileProvider.getUriForFile(
                        this, "$packageName.fileprovider", File(path),
                    )
                    startActivity(
                        Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(
                                uri,
                                "application/vnd.android.package-archive",
                            )
                            addFlags(
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_ACTIVITY_NEW_TASK,
                            )
                        },
                    )
                    result.success(true)
                } catch (e: Exception) {
                    result.error("install_failed", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    companion object {
        private var wifiLock: WifiManager.WifiLock? = null
        private var wakeLock: PowerManager.WakeLock? = null

        /// Acquiert (hold=true) ou relâche (hold=false) les verrous réseau, de
        /// façon idempotente. Toute exception est avalée : un échec de verrou ne
        /// doit jamais interrompre la lecture.
        @Synchronized
        private fun setNetworkLock(context: Context, hold: Boolean) {
            try {
                if (wifiLock == null) {
                    val wm = context.getSystemService(Context.WIFI_SERVICE) as WifiManager
                    @Suppress("DEPRECATION")
                    wifiLock = wm.createWifiLock(
                        WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                        "gullify:playback",
                    ).apply { setReferenceCounted(false) }
                }
                if (wakeLock == null) {
                    val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                    wakeLock = pm.newWakeLock(
                        PowerManager.PARTIAL_WAKE_LOCK,
                        "gullify:playback",
                    ).apply { setReferenceCounted(false) }
                }
                if (hold) {
                    if (wifiLock?.isHeld == false) wifiLock?.acquire()
                    if (wakeLock?.isHeld == false) wakeLock?.acquire()
                } else {
                    if (wifiLock?.isHeld == true) wifiLock?.release()
                    if (wakeLock?.isHeld == true) wakeLock?.release()
                }
            } catch (_: Exception) {
            }
        }
    }
}
