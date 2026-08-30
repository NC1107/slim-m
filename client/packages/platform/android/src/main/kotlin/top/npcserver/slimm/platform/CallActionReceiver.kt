// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
package top.npcserver.slimm.platform

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationManagerCompat

/**
 * Handles the incoming-call notification's Answer and Decline actions.
 *
 * The notification is cancelled unconditionally here regardless of which
 * action fired or whether a [SlimmConnection] is still reachable, since
 * that is the one thing that must always happen. Driving the connection
 * itself, when one is still in [SlimmConnection.registry], reuses its own
 * [SlimmConnection.onAnswer]/[SlimmConnection.onReject] rather than
 * duplicating what those already do (state transition, ending the
 * connection, and - for Answer - opening the app): a call reported to
 * Telecom is answered or declined exactly once, from whichever surface the
 * user actually used.
 *
 * A missing connection - `addNewIncomingCall` never reached
 * [SlimmConnectionService], or the process restarted and lost the
 * in-memory registry - is not a dropped call: Decline still has nothing
 * further to do once the notification is gone, and Answer still opens the
 * app directly, the same fallback this receiver has always had.
 */
class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val notificationId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, -1)
        if (notificationId != -1) {
            NotificationManagerCompat.from(context).cancel(notificationId)
        }
        val connection = intent.getStringExtra(EXTRA_CALL_ID)?.let { SlimmConnection.registry[it] }
        when (intent.action) {
            ACTION_ANSWER -> {
                if (connection != null) {
                    connection.onAnswer()
                } else {
                    context.startActivity(IncomingCallNotifier.openAppIntent(context))
                }
            }
            ACTION_DECLINE -> connection?.onReject()
        }
    }

    companion object {
        const val ACTION_ANSWER = "top.npcserver.slimm.action.ANSWER_CALL"
        const val ACTION_DECLINE = "top.npcserver.slimm.action.DECLINE_CALL"
        const val EXTRA_NOTIFICATION_ID = "notification_id"
        const val EXTRA_CALL_ID = "call_id"
    }
}
