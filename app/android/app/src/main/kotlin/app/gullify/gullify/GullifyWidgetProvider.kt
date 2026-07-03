package app.gullify.gullify

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.view.KeyEvent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Widget d'écran d'accueil : pochette + titre + précédent/lecture/suivant.
 * Les boutons envoient des événements « bouton média » au receiver
 * d'audio_service — aucun canal spécifique n'est nécessaire, le service
 * audio les traite comme un casque Bluetooth.
 */
class GullifyWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val data = HomeWidgetPlugin.getData(context)
        val title = data.getString("title", null) ?: "Gullify"
        val artist = data.getString("artist", null) ?: ""
        val playing = data.getBoolean("playing", false)
        val artPath = data.getString("artPath", null)

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.gullify_widget)
            views.setTextViewText(R.id.widget_title, title)
            views.setTextViewText(R.id.widget_artist, artist)
            views.setImageViewResource(
                R.id.widget_play,
                if (playing) android.R.drawable.ic_media_pause
                else android.R.drawable.ic_media_play,
            )

            val art = artPath?.let { BitmapFactory.decodeFile(it) }
            if (art != null) {
                views.setImageViewBitmap(R.id.widget_art, art)
            } else {
                views.setImageViewResource(R.id.widget_art, R.mipmap.ic_launcher)
            }

            views.setOnClickPendingIntent(
                R.id.widget_prev,
                mediaButton(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS, 1),
            )
            views.setOnClickPendingIntent(
                R.id.widget_play,
                mediaButton(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 2),
            )
            views.setOnClickPendingIntent(
                R.id.widget_next,
                mediaButton(context, KeyEvent.KEYCODE_MEDIA_NEXT, 3),
            )

            // Tap ailleurs : ouvre l'app.
            context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?.let { launch ->
                    views.setOnClickPendingIntent(
                        R.id.widget_root,
                        PendingIntent.getActivity(
                            context, 0, launch,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                        ),
                    )
                }

            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun mediaButton(
        context: Context,
        keyCode: Int,
        requestCode: Int,
    ): PendingIntent {
        val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            setClass(context, com.ryanheise.audioservice.MediaButtonReceiver::class.java)
            putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        }
        return PendingIntent.getBroadcast(
            context, requestCode, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
