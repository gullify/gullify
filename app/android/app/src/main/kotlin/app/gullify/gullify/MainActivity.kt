package app.gullify.gullify

import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.audiofx.Equalizer
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager
import android.view.WindowManager
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.math.roundToInt

class MainActivity : AudioServiceActivity() {
    /// Voie du réveil (idée #81) : l'app y demande la programmation, et le
    /// natif y annonce une sonnerie quand l'activité est déjà ouverte.
    private var alarmChannel: MethodChannel? = null

    /// Sonnerie arrivée avant que Flutter n'écoute (démarrage à froid) : elle
    /// attend ici que l'app vienne la chercher.
    private var alarmLaunch = false

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent?.getBooleanExtra(GullifyAlarm.EXTRA_ALARM, false) == true) {
            alarmLaunch = true
            showOverLockScreen()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra(GullifyAlarm.EXTRA_ALARM, false)) {
            alarmLaunch = true
            showOverLockScreen()
            // L'app tournait déjà : personne ne viendra relire le drapeau au
            // démarrage, on la prévient tout de suite.
            alarmChannel?.invokeMethod("ring", null)
        }
    }

    /// Le réveil s'affiche par-dessus l'écran verrouillé et rallume l'écran :
    /// sinon, la sonnerie se joue derrière un écran noir.
    private fun showOverLockScreen() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(true)
                setTurnScreenOn(true)
            } else {
                @Suppress("DEPRECATION")
                window.addFlags(
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                )
            }
        } catch (_: Exception) {
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Réveil matinal (idée #81) : la programmation vit côté natif (une
        // alarme exacte survit à l'app fermée et au redémarrage du téléphone),
        // le choix de la musique côté Flutter.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "gullify/alarm",
        ).also { channel ->
            alarmChannel = channel
            channel.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "configure" -> result.success(
                            GullifyAlarm.configure(
                                applicationContext,
                                call.argument<Boolean>("enabled") ?: false,
                                call.argument<Int>("hour") ?: 7,
                                call.argument<Int>("minute") ?: 0,
                                call.argument<Int>("days") ?: 0,
                            ),
                        )
                        "armAt" -> {
                            GullifyAlarm.armAt(
                                applicationContext,
                                (call.argument<Number>("at") ?: 0).toLong(),
                            )
                            result.success(true)
                        }
                        "cancel" -> {
                            GullifyAlarm.cancel(applicationContext)
                            result.success(true)
                        }
                        "nextRing" -> result.success(GullifyAlarm.nextRing(applicationContext))
                        "pendingRing" ->
                            result.success(GullifyAlarm.pendingRing(applicationContext))
                        "handled" -> {
                            GullifyAlarm.handled(applicationContext)
                            result.success(true)
                        }
                        "canRingExactly" ->
                            result.success(GullifyAlarm.canRingExactly(applicationContext))
                        "requestExactPermission" -> {
                            GullifyAlarm.requestExactPermission(this)
                            result.success(true)
                        }
                        "setMediaVolume" -> result.success(
                            GullifyAlarm.setMediaVolume(
                                applicationContext,
                                call.argument<Int>("percent") ?: 60,
                            ),
                        )
                        "restoreMediaVolume" -> {
                            GullifyAlarm.restoreMediaVolume(applicationContext)
                            result.success(true)
                        }
                        // Drapeau du démarrage à froid, consommé une seule fois.
                        "launchedByAlarm" -> {
                            result.success(alarmLaunch)
                            alarmLaunch = false
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("alarm_failed", e.message, null)
                }
            }
        }

        // Google TV : l'app doit savoir dès le démarrage si elle s'ouvre sur un
        // téléviseur, parce que l'interface à dix pieds n'a rien à voir avec
        // celle du téléphone — et qu'il n'y a pas de doigt pour la manœuvrer.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "gullify/device",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isTelevision" -> result.success(isTelevision())
                else -> result.notImplemented()
            }
        }

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
        // Égaliseur système, attaché à la session audio du lecteur. On ne passe
        // plus par l'AudioPipeline de just_audio : il lit les bandes au moment
        // où il active le lecteur, avant qu'ExoPlayer (media3 1.9) n'ait généré
        // sa session audio en tâche de fond. L'effet n'existe alors pas encore
        // côté natif et l'exception qui en découlait empoisonnait le lecteur —
        // plus aucune chanson ne démarrait (idée #47). Ici, un échec ne touche
        // que l'écran de réglage.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "gullify/equalizer",
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "bind" -> result.success(
                        bindEqualizer(
                            call.argument<Int>("sessionId")!!,
                            call.argument<Boolean>("enabled") ?: false,
                            call.argument<List<Double>>("gains") ?: emptyList(),
                        ),
                    )
                    "setEnabled" -> {
                        // setEnabled renvoie un code Android (pas un setter de
                        // propriété Kotlin) : on l'appelle explicitement.
                        equalizer?.setEnabled(call.argument<Boolean>("enabled")!!)
                        result.success(true)
                    }
                    "setBandGain" -> {
                        setBandGain(
                            call.argument<Int>("index")!!,
                            call.argument<Double>("gain")!!,
                        )
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("eq_unavailable", e.message, null)
            }
        }
    }

    /// Téléviseur ou pas.
    ///
    /// `FEATURE_LEANBACK` est la réponse officielle d'Android, mais quelques
    /// boîtiers et émulateurs ne la déclarent pas tout en tournant bel et bien
    /// en mode télévision — d'où le second test. Au moindre doute on répond
    /// « non » : servir l'interface TV à un téléphone serait bien pire que
    /// l'inverse.
    private fun isTelevision(): Boolean = try {
        val pm = packageManager
        val leanback = pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            pm.hasSystemFeature("android.software.leanback")
        val uiMode = (getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager)
            ?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
        leanback || uiMode
    } catch (_: Exception) {
        false
    }

    companion object {
        private var wifiLock: WifiManager.WifiLock? = null
        private var wakeLock: PowerManager.WakeLock? = null
        private var equalizer: Equalizer? = null
        private var equalizerSession: Int? = null

        /// Crée (ou réutilise) l'égaliseur de la session audio donnée, y rejoue
        /// les réglages mémorisés par l'app, et renvoie les bandes de
        /// l'appareil. Une nouvelle session = un nouvel effet : l'ancien est
        /// relâché pour ne pas fuir.
        @Synchronized
        private fun bindEqualizer(
            sessionId: Int,
            enabled: Boolean,
            gains: List<Double>,
        ): Map<String, Any> {
            if (equalizerSession != sessionId) {
                try {
                    equalizer?.release()
                } catch (_: Exception) {
                }
                equalizer = null
                equalizerSession = null
                equalizer = Equalizer(0, sessionId)
                equalizerSession = sessionId
            }
            val eq = equalizer!!
            val range = eq.bandLevelRange // en milliBels
            val bandCount = eq.numberOfBands.toInt()
            for (i in 0 until bandCount) {
                val gain = gains.getOrNull(i) ?: continue
                eq.setBandLevel(
                    i.toShort(),
                    millibels(gain, range),
                )
            }
            eq.setEnabled(enabled)
            return mapOf(
                "minDecibels" to range[0] / 100.0,
                "maxDecibels" to range[1] / 100.0,
                "bands" to (0 until bandCount).map { i ->
                    mapOf(
                        "index" to i,
                        // getCenterFreq renvoie des milliHertz, on veut des Hz.
                        "centerFrequency" to eq.getCenterFreq(i.toShort()) / 1000.0,
                        "gain" to eq.getBandLevel(i.toShort()) / 100.0,
                    )
                },
            )
        }

        @Synchronized
        private fun setBandGain(index: Int, gain: Double) {
            val eq = equalizer ?: return
            eq.setBandLevel(index.toShort(), millibels(gain, eq.bandLevelRange))
        }

        /// dB (côté app) → milliBels bornés à la plage de l'appareil (Android
        /// rejette toute valeur hors plage).
        private fun millibels(decibels: Double, range: ShortArray): Short =
            (decibels * 100.0).roundToInt()
                .coerceIn(range[0].toInt(), range[1].toInt())
                .toShort()

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
