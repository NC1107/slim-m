// SPDX-License-Identifier: Apache-2.0
package top.npcserver.slimm.platform

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationManagerCompat

/**
 * Handles the incoming-call notification's Decline action.
 *
 * There is no `android.telecom` call to end and no RTC session yet joined
 * (see the PR description), so declining has exactly one honest effect:
 * take the notification off screen. Answering, by contrast, opens the app
 * itself (a plain `PendingIntent.getActivity`) rather than routing here,
 * since there is nothing further this receiver could do for it.
 */
class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_DECLINE) return
        val notificationId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, -1)
        if (notificationId == -1) return
        NotificationManagerCompat.from(context).cancel(notificationId)
    }

    companion object {
        const val ACTION_DECLINE = "top.npcserver.slimm.action.DECLINE_CALL"
        const val EXTRA_NOTIFICATION_ID = "notification_id"
    }
}
