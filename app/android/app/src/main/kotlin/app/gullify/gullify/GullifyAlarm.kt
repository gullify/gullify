package app.gullify.gullify

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.RingtoneManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.util.Calendar
import kotlin.math.roundToInt

/// Le réveil matinal (idée #81), côté Android.
///
/// Une alarme exacte (`setAlarmClock`, la seule que le sommeil profond
/// n'écarte pas) réveille le téléphone à l'heure dite. Au déclenchement,
/// [AlarmReceiver] publie une notification à ouverture plein écran qui lance
/// l'app : c'est Flutter qui choisit la musique et fait monter le volume.
///
/// Le mode d'échec d'un réveil est SILENCIEUX — il compile, et il ne sonne
/// pas. D'où les trois filets :
///   1. `setAlarmClock` quand l'alarme exacte est permise, sinon
///      `setAndAllowWhileIdle` (à quelques minutes près, mais ça sonne) ;
///   2. la notification tente aussi d'ouvrir l'activité directement ;
///   3. une alarme de secours 90 s plus tard fait sonner la sonnerie SYSTÈME
///      tant que l'app n'a pas dit « j'ai pris le relais » ([handled]).
/// L'heure programmée est mémorisée côté natif : après un redémarrage du
/// téléphone, Android oublie toutes les alarmes et c'est [rearm] qui la
/// repose, sans que l'app ait besoin d'être ouverte.
object GullifyAlarm {
    const val EXTRA_ALARM = "gullify_alarm"
    const val ACTION_RING = "app.gullify.gullify.ALARM_RING"
    const val ACTION_SAFETY = "app.gullify.gullify.ALARM_SAFETY"

    private const val PREFS = "gullify_alarm"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_HOUR = "hour"
    private const val KEY_MINUTE = "minute"
    private const val KEY_DAYS = "days"
    private const val KEY_NEXT = "next"
    private const val KEY_FIRED = "fired"
    private const val KEY_SAFETY_LEFT = "safety_left"
    private const val KEY_VOLUME_BEFORE = "volume_before"

    private const val CHANNEL_RING = "gullify_alarm"
    private const val CHANNEL_BUZZ = "gullify_alarm_buzz"
    private const val NOTIF_RING = 4181
    private const val NOTIF_BUZZ = 4182
    private const val REQ_RING = 4181
    private const val REQ_SAFETY = 4182
    private const val REQ_SHOW = 4183
    private const val REQ_OPEN = 4184

    /// Délai avant le filet audible, et nombre de rappels : au-delà, un
    /// téléphone oublié à la maison ne sonne pas toute la journée.
    private const val SAFETY_DELAY_MS = 90_000L
    private const val SAFETY_ROUNDS = 5

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun alarms(context: Context) =
        context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    private fun notifications(context: Context) =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    // ── Programmation ────────────────────────────────────────────────────────

    /// Retient le réglage et pose (ou retire) l'alarme. Renvoie l'heure de la
    /// prochaine sonnerie, ou 0 si le réveil est éteint.
    ///
    /// [days] est un masque de jours (bit 0 = lundi … bit 6 = dimanche) ;
    /// 0 veut dire « tous les jours ».
    fun configure(
        context: Context,
        enabled: Boolean,
        hour: Int,
        minute: Int,
        days: Int,
    ): Long {
        prefs(context).edit()
            .putBoolean(KEY_ENABLED, enabled)
            .putInt(KEY_HOUR, hour)
            .putInt(KEY_MINUTE, minute)
            .putInt(KEY_DAYS, days)
            .apply()
        if (!enabled) {
            cancel(context)
            return 0L
        }
        val at = nextTrigger(hour, minute, days, System.currentTimeMillis())
        armAt(context, at)
        return at
    }

    /// Pose l'alarme à une heure précise (prochaine occurrence, rappel de
    /// « encore 9 minutes », ou essai à une minute d'ici).
    fun armAt(context: Context, at: Long) {
        val am = alarms(context)
        val fire = PendingIntent.getBroadcast(
            context,
            REQ_RING,
            Intent(context, AlarmReceiver::class.java).setAction(ACTION_RING),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        try {
            if (canRingExactly(context)) {
                // setAlarmClock : la seule programmation qu'Android ne décale
                // pas en sommeil profond, et elle affiche l'icône de réveil
                // dans la barre d'état (Maxime voit que c'est armé).
                am.setAlarmClock(AlarmManager.AlarmClockInfo(at, showIntent(context)), fire)
            } else {
                // Permission d'alarme exacte refusée : à quelques minutes près,
                // mais un réveil approximatif vaut mieux qu'un réveil muet.
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, fire)
            }
            prefs(context).edit().putLong(KEY_NEXT, at).apply()
        } catch (_: Exception) {
            // Constructeur exotique, permission retirée entre-temps : on ne
            // fait pas planter l'app pour ça, l'écran de réglage le dira.
            prefs(context).edit().putLong(KEY_NEXT, 0L).apply()
        }
    }

    fun cancel(context: Context) {
        val am = alarms(context)
        listOf(
            REQ_RING to ACTION_RING,
            REQ_SAFETY to ACTION_SAFETY,
        ).forEach { (req, action) ->
            val pi = PendingIntent.getBroadcast(
                context,
                req,
                Intent(context, AlarmReceiver::class.java).setAction(action),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            try {
                am.cancel(pi)
            } catch (_: Exception) {
            }
        }
        notifications(context).cancel(NOTIF_RING)
        notifications(context).cancel(NOTIF_BUZZ)
        prefs(context).edit().putLong(KEY_NEXT, 0L).apply()
    }

    /// Repose l'alarme après un redémarrage du téléphone : Android efface
    /// toutes les alarmes au reboot, et l'app, elle, n'est pas ouverte.
    fun rearm(context: Context) {
        val p = prefs(context)
        if (!p.getBoolean(KEY_ENABLED, false)) return
        configure(
            context,
            true,
            p.getInt(KEY_HOUR, 7),
            p.getInt(KEY_MINUTE, 0),
            p.getInt(KEY_DAYS, 0),
        )
    }

    fun nextRing(context: Context): Long = prefs(context).getLong(KEY_NEXT, 0L)

    /// La sonnerie qui vient de retentir et que l'app n'a pas encore reprise —
    /// 0 s'il n'y a rien en attente. Sert au rattrapage : notification
    /// ouverte trois minutes plus tard, l'app doit quand même jouer.
    fun pendingRing(context: Context): Long = prefs(context).getLong(KEY_FIRED, 0L)

    /// L'app a pris le relais : plus de filet audible, plus de notification.
    fun handled(context: Context) {
        val am = alarms(context)
        try {
            am.cancel(
                PendingIntent.getBroadcast(
                    context,
                    REQ_SAFETY,
                    Intent(context, AlarmReceiver::class.java).setAction(ACTION_SAFETY),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
        } catch (_: Exception) {
        }
        notifications(context).cancel(NOTIF_RING)
        notifications(context).cancel(NOTIF_BUZZ)
        prefs(context).edit().putLong(KEY_FIRED, 0L).putInt(KEY_SAFETY_LEFT, 0).apply()
    }

    /// L'alarme exacte est-elle permise ? (Android 12+ peut la refuser ; sans
    /// elle le réveil sonne « quand Android voudra bien ».)
    fun canRingExactly(context: Context): Boolean = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            alarms(context).canScheduleExactAlarms()
        } else {
            true
        }
    } catch (_: Exception) {
        false
    }

    /// Ouvre le réglage système de l'alarme exacte (rien à faire avant
    /// Android 12, où elle est acquise).
    fun requestExactPermission(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        try {
            context.startActivity(
                Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                    .setData(android.net.Uri.parse("package:${context.packageName}"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (_: Exception) {
        }
    }

    // ── Volume ───────────────────────────────────────────────────────────────

    /// Monte le volume média au niveau voulu et retient celui d'avant : un
    /// réveil qui sonne dans un téléphone laissé muet la veille ne réveille
    /// personne. Renvoie faux si le mode « ne pas déranger » l'interdit.
    fun setMediaVolume(context: Context, percent: Int): Boolean = try {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val before = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
        prefs(context).edit().putInt(KEY_VOLUME_BEFORE, before).apply()
        val target = (max * percent.coerceIn(0, 100) / 100.0).roundToInt().coerceIn(1, max)
        audio.setStreamVolume(AudioManager.STREAM_MUSIC, target, 0)
        true
    } catch (_: Exception) {
        false
    }

    /// Remet le volume média tel qu'il était avant la sonnerie : le réveil
    /// n'a pas à décider du volume de la journée.
    fun restoreMediaVolume(context: Context) {
        try {
            val before = prefs(context).getInt(KEY_VOLUME_BEFORE, -1)
            if (before < 0) return
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audio.setStreamVolume(AudioManager.STREAM_MUSIC, before, 0)
            prefs(context).edit().putInt(KEY_VOLUME_BEFORE, -1).apply()
        } catch (_: Exception) {
        }
    }

    // ── Déclenchement ────────────────────────────────────────────────────────

    /// L'heure a sonné : réveiller le processeur, ouvrir l'app, armer le
    /// filet, et reposer l'occurrence suivante.
    fun ring(context: Context) {
        wake(context)
        prefs(context).edit()
            .putLong(KEY_FIRED, System.currentTimeMillis())
            .putInt(KEY_SAFETY_LEFT, SAFETY_ROUNDS)
            .apply()

        ensureChannels(context)
        val open = openIntent(context)
        val notification = NotificationCompat.Builder(context, CHANNEL_RING)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Réveil Gullify")
            .setContentText("C'est l'heure — la musique arrive.")
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setContentIntent(open)
            .setFullScreenIntent(open, true)
            .build()
        try {
            notifications(context).notify(NOTIF_RING, notification)
        } catch (_: Exception) {
        }
        // Deuxième chance : ouvrir l'activité directement. Android l'autorise
        // rarement depuis l'arrière-plan, mais quand il l'autorise, l'app
        // s'ouvre sans que la notification ait à être touchée.
        try {
            context.startActivity(activityIntent(context))
        } catch (_: Exception) {
        }

        armSafety(context)
        // La sonnerie de demain se pose maintenant : si Maxime n'ouvre jamais
        // l'app, le réveil de demain existe quand même.
        val p = prefs(context)
        if (p.getBoolean(KEY_ENABLED, false)) {
            val at = nextTrigger(
                p.getInt(KEY_HOUR, 7),
                p.getInt(KEY_MINUTE, 0),
                p.getInt(KEY_DAYS, 0),
                System.currentTimeMillis() + 60_000L,
            )
            armAt(context, at)
        }
    }

    /// Le filet : l'app n'a pas répondu, on fait sonner la sonnerie système.
    fun buzz(context: Context) {
        wake(context)
        val p = prefs(context)
        // L'app a pris le relais entre-temps : plus rien à faire.
        if (p.getLong(KEY_FIRED, 0L) == 0L) return
        val left = p.getInt(KEY_SAFETY_LEFT, 0)
        if (left <= 0) return
        p.edit().putInt(KEY_SAFETY_LEFT, left - 1).apply()

        ensureChannels(context)
        val open = openIntent(context)
        val notification = NotificationCompat.Builder(context, CHANNEL_BUZZ)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Réveil Gullify")
            .setContentText("L'app n'a pas démarré — touche pour ouvrir Gullify.")
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(open)
            .setFullScreenIntent(open, true)
            .setAutoCancel(true)
            .build()
        try {
            notifications(context).notify(NOTIF_BUZZ, notification)
        } catch (_: Exception) {
        }
        try {
            context.startActivity(activityIntent(context))
        } catch (_: Exception) {
        }
        armSafety(context)
    }

    private fun armSafety(context: Context) {
        val at = System.currentTimeMillis() + SAFETY_DELAY_MS
        val pi = PendingIntent.getBroadcast(
            context,
            REQ_SAFETY,
            Intent(context, AlarmReceiver::class.java).setAction(ACTION_SAFETY),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        try {
            alarms(context).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        } catch (_: Exception) {
        }
    }

    /// Garde le processeur éveillé le temps que Flutter démarre et lance la
    /// musique — sans ce verrou, le téléphone peut se rendormir entre la
    /// notification et la première note.
    private fun wake(context: Context) {
        try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "gullify:alarm")
                .apply { setReferenceCounted(false) }
                .acquire(120_000L)
        } catch (_: Exception) {
        }
    }

    private fun ensureChannels(context: Context) {
        val nm = NotificationManagerCompat.from(context)
        // Canal du réveil : muet, c'est l'app qui fait le son (fondu montant).
        val ring = NotificationChannelCompat
            .Builder(CHANNEL_RING, NotificationManagerCompat.IMPORTANCE_HIGH)
            .setName("Réveil")
            .setDescription("Sonnerie du réveil matinal")
            .setSound(null, null)
            .setVibrationEnabled(false)
            .build()
        // Canal du filet : sonnerie système, pour le cas où l'app ne démarre pas.
        val buzz = NotificationChannelCompat
            .Builder(CHANNEL_BUZZ, NotificationManagerCompat.IMPORTANCE_HIGH)
            .setName("Réveil — secours")
            .setDescription("Sonnerie de secours si l'app ne démarre pas")
            .setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            .setVibrationEnabled(true)
            .build()
        try {
            nm.createNotificationChannel(ring)
            nm.createNotificationChannel(buzz)
        } catch (_: Exception) {
        }
    }

    private fun activityIntent(context: Context) =
        Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .putExtra(EXTRA_ALARM, true)
            .addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT,
            )

    private fun openIntent(context: Context): PendingIntent = PendingIntent.getActivity(
        context,
        REQ_OPEN,
        activityIntent(context),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /// L'intent que le système montre quand on touche l'icône de réveil de la
    /// barre d'état (obligatoire pour setAlarmClock).
    private fun showIntent(context: Context): PendingIntent = PendingIntent.getActivity(
        context,
        REQ_SHOW,
        Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /// La prochaine occurrence de [hour]:[minute] après [now], en tenant
    /// compte du masque de jours ([days] = 0 : tous les jours).
    ///
    /// Passe par Calendar plutôt que par une addition de millisecondes : un
    /// changement d'heure ne doit pas décaler le réveil d'une heure.
    fun nextTrigger(hour: Int, minute: Int, days: Int, now: Long): Long {
        val base = Calendar.getInstance().apply {
            timeInMillis = now
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        for (i in 0..7) {
            val day = (base.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, i) }
            if (day.timeInMillis <= now) continue
            // Calendar : dimanche = 1 … samedi = 7. Ici lundi = bit 0.
            val iso = ((day.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1
            if (days == 0 || (days and (1 shl (iso - 1))) != 0) return day.timeInMillis
        }
        return base.timeInMillis + 86_400_000L
    }
}

/// Reçoit l'alarme, son filet, et le redémarrage du téléphone.
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            Intent.ACTION_MY_PACKAGE_REPLACED,
            -> GullifyAlarm.rearm(context)
            GullifyAlarm.ACTION_SAFETY -> GullifyAlarm.buzz(context)
            else -> GullifyAlarm.ring(context)
        }
    }
}
