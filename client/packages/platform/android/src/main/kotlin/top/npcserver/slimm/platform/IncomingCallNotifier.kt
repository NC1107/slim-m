// SPDX-License-Identifier: Apache-2.0
package top.npcserver.slimm.platform

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person

/**
 * Builds and posts this app's incoming-call notification.
 *
 * One `NotificationCompat.CallStyle` code path covers every API level this
 * app ships (minSdk 24): androidx renders the real `Notification.CallStyle`
 * chrome on API 31+, and an equivalent plain notification with the same
 * answer and decline actions on everything older, entirely inside the
 * compat library. There is no ConnectionService/`android.telecom`
 * registration here - see the PR description for why a notification is the
 * whole story rather than a system-managed call.
 */
class IncomingCallNotifier(private val context: Context) {
    /**
     * Shows, or replaces, the incoming-call notification for [callId].
     *
     * [NotificationManagerCompat.canUseFullScreenIntent] is checked on every
     * call rather than once, since the user can flip Android 14's
     * full-screen-notifications toggle while this notifier is alive.
     */
    fun showIncomingCall(callId: String, callerName: String) {
        ensureChannel()
        val notificationId = notificationIdFor(callId)
        val person = Person.Builder().setName(callerName).build()
        val answerIntent = openAppPendingIntent(notificationId)
        val declineIntent = declinePendingIntent(notificationId)

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(smallIconResId())
            .setContentTitle(callerName)
            .setContentText(CONTENT_TEXT)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(answerIntent)
            .setStyle(NotificationCompat.CallStyle.forIncomingCall(person, declineIntent, answerIntent))

        if (NotificationManagerCompat.from(context).canUseFullScreenIntent()) {
            builder.setFullScreenIntent(answerIntent, true)
        }

        try {
            NotificationManagerCompat.from(context).notify(notificationId, builder.build())
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS denied (API 33+); nothing else to do here.
        }
    }

    private fun ensureChannel() {
        val channel = NotificationChannelCompat.Builder(
            CHANNEL_ID,
            NotificationManagerCompat.IMPORTANCE_HIGH,
        )
            .setName(CHANNEL_NAME)
            .setDescription("Incoming calls.")
            .build()
        NotificationManagerCompat.from(context).createNotificationChannel(channel)
    }

    private fun openAppPendingIntent(requestCode: Int): PendingIntent {
        val launchIntent =
            context.packageManager.getLaunchIntentForPackage(context.packageName) ?: Intent()
        launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        return PendingIntent.getActivity(
            context,
            requestCode,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun declinePendingIntent(notificationId: Int): PendingIntent {
        val intent = Intent(context, CallActionReceiver::class.java)
            .setAction(CallActionReceiver.ACTION_DECLINE)
            .putExtra(CallActionReceiver.EXTRA_NOTIFICATION_ID, notificationId)
        return PendingIntent.getBroadcast(
            context,
            notificationId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun smallIconResId(): Int {
        val resId = context.resources.getIdentifier(
            "ic_stat_notify",
            "drawable",
            context.packageName,
        )
        return if (resId != 0) resId else context.applicationInfo.icon
    }

    companion object {
        const val CHANNEL_ID = "calls_v1"
        private const val CHANNEL_NAME = "Calls"
        private const val CONTENT_TEXT = "slim-m"

        /** Stable across a repeat push for the same call; see the class doc. */
        fun notificationIdFor(callId: String): Int = callId.hashCode()
    }
}
