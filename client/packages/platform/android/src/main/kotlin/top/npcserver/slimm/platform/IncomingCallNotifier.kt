// SPDX-License-Identifier: Apache-2.0
package top.npcserver.slimm.platform

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.app.PendingIntent
import android.os.Bundle
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person

/**
 * Builds and posts this app's incoming-call notification, and reports the
 * same call to `android.telecom` as a self-managed connection.
 *
 * One `NotificationCompat.CallStyle` code path covers every API level this
 * app ships (minSdk 24): androidx renders the real `Notification.CallStyle`
 * chrome on API 31+, and an equivalent plain notification with the same
 * answer and decline actions on everything older, entirely inside the
 * compat library. The notification stays the whole on-screen surface -
 * Telecom does not draw one on a self-managed app's behalf - so
 * [reportToTelecom] only ever affects audio focus and routing, and the
 * system's own call bookkeeping (Bluetooth, Do Not Disturb, the ongoing-
 * call indicator), never what answer/decline look like. See
 * [SlimmConnection]'s own doc for why answering ends the Telecom call
 * immediately rather than leaving it "active" indefinitely.
 */
class IncomingCallNotifier(private val context: Context) {
    /**
     * Shows, or replaces, the incoming-call notification for [callId], and
     * best-effort reports the same call to Telecom.
     *
     * [NotificationManagerCompat.canUseFullScreenIntent] is checked on every
     * call rather than once, since the user can flip Android 14's
     * full-screen-notifications toggle while this notifier is alive.
     */
    fun showIncomingCall(callId: String, callerName: String) {
        ensureChannel()
        val notificationId = notificationIdFor(callId)
        val person = Person.Builder().setName(callerName).build()
        val openApp = openAppPendingIntent(notificationId)
        val answerIntent = actionPendingIntent(
            notificationId,
            callId,
            CallActionReceiver.ACTION_ANSWER,
        )
        val declineIntent = actionPendingIntent(
            notificationId,
            callId,
            CallActionReceiver.ACTION_DECLINE,
        )

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(smallIconResId())
            .setContentTitle(callerName)
            .setContentText(CONTENT_TEXT)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(openApp)
            .setStyle(NotificationCompat.CallStyle.forIncomingCall(person, declineIntent, answerIntent))

        if (NotificationManagerCompat.from(context).canUseFullScreenIntent()) {
            // Full-screen intents must launch an Activity directly - Telecom
            // is not consulted here, unlike the CallStyle action buttons
            // above, since a locked screen has no user tap to route through
            // CallActionReceiver in the first place.
            builder.setFullScreenIntent(openApp, true)
        }

        try {
            NotificationManagerCompat.from(context).notify(notificationId, builder.build())
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS denied (API 33+); nothing else to do here.
        }

        reportToTelecom(callId, callerName)
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

    /**
     * Registers this app's self-managed `PhoneAccount` (idempotent: Telecom
     * treats a re-registration of the same handle as an update, not an
     * error) and reports [callId] as a new incoming call, so
     * [SlimmConnectionService] is asked for a [SlimmConnection].
     *
     * Best-effort past this point on purpose: `MANAGE_OWN_CALLS` is a normal
     * permission and needs no runtime prompt, but the account can still be
     * disabled by the user in Settings > Calling accounts, and some AOSP
     * forks carry no Telecom subsystem at all. Either way the notification
     * already posted above is the whole call surface regardless of whether
     * this succeeds.
     */
    private fun reportToTelecom(callId: String, callerName: String) {
        val telecomManager =
            context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager ?: return
        val handle = phoneAccountHandle(context)
        val account = PhoneAccount.builder(handle, CONTENT_TEXT)
            .setCapabilities(PhoneAccount.CAPABILITY_SELF_MANAGED)
            .build()
        val extras = Bundle().apply {
            putString(SlimmConnection.EXTRA_CALL_ID, callId)
            putString(SlimmConnection.EXTRA_CALLER_NAME, callerName)
        }
        try {
            telecomManager.registerPhoneAccount(account)
            telecomManager.addNewIncomingCall(handle, extras)
        } catch (_: SecurityException) {
            // MANAGE_OWN_CALLS refused, or the account isn't enabled yet.
        } catch (_: IllegalStateException) {
            // No Telecom subsystem on this build.
        }
    }

    private fun actionPendingIntent(
        notificationId: Int,
        callId: String,
        action: String,
    ): PendingIntent {
        val intent = Intent(context, CallActionReceiver::class.java)
            .setAction(action)
            .putExtra(CallActionReceiver.EXTRA_NOTIFICATION_ID, notificationId)
            .putExtra(CallActionReceiver.EXTRA_CALL_ID, callId)
        return PendingIntent.getBroadcast(
            context,
            notificationId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun openAppPendingIntent(requestCode: Int): PendingIntent =
        PendingIntent.getActivity(
            context,
            requestCode,
            openAppIntent(context),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

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
        private const val PHONE_ACCOUNT_ID = "slimm_calls"

        /** Stable across a repeat push for the same call; see the class doc. */
        fun notificationIdFor(callId: String): Int = callId.hashCode()

        /**
         * The one `PhoneAccountHandle` this app registers - a single self-
         * managed account covers every call, the same way one notification
         * channel does, so there is nothing per-call to register or leak.
         */
        fun phoneAccountHandle(context: Context): PhoneAccountHandle =
            PhoneAccountHandle(
                ComponentName(context, SlimmConnectionService::class.java),
                PHONE_ACCOUNT_ID,
            )

        /**
         * What a tap on this notification, an answered CallStyle action, or
         * a Telecom-driven answer all resolve to: opening the app itself.
         * There is no RTC session to join from here (see [SlimmConnection]'s
         * own doc), so opening the app is the entire answer, on every path
         * that can trigger it.
         */
        fun openAppIntent(context: Context): Intent {
            val launchIntent =
                context.packageManager.getLaunchIntentForPackage(context.packageName)
                    ?: Intent()
            launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            return launchIntent
        }
    }
}
