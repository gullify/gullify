package app.gullify.gullify

import android.content.Intent
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
}
