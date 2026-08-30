// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
package top.npcserver.slimm.platform

import android.content.Context
import android.net.Uri
import android.telecom.Connection
import android.telecom.DisconnectCause
import android.telecom.TelecomManager
import androidx.core.app.NotificationManagerCompat

/**
 * One in-flight incoming call reported to `android.telecom`.
 *
 * There is no RTC session behind this connection - the same honest limit
 * [CallActionReceiver]'s own doc comment already states for Decline - so
 * this class exists only to give the *ringing* phase proper Telecom
 * treatment (audio focus and routing, Bluetooth, Do Not Disturb, the
 * system's own ongoing-call bookkeeping) while the notification is on
 * screen, and to keep that bookkeeping in sync with whatever
 * [CallActionReceiver] or Telecom itself decides next.
 *
 * Answering ends this connection immediately rather than leaving it
 * reported as active: there is no bridge yet from the in-app voice session
 * back to a Telecom connection (that would need `VoiceController` wired the
 * same way `CallLifecycleChannel` already wires iOS's CallKit), and a
 * connection left "active" with nothing that will ever end it would show a
 * ghost ongoing call in the system's own UI forever - worse than the plain
 * notification this replaces. Reporting the ringing phase is the whole,
 * honest scope of this class.
 */
class SlimmConnection(
    private val context: Context,
    private val callId: String,
    callerName: String,
) : Connection() {
    init {
        setCallerDisplayName(callerName, TelecomManager.PRESENTATION_ALLOWED)
        setAddress(
            Uri.fromParts(ADDRESS_SCHEME, callId, null),
            TelecomManager.PRESENTATION_ALLOWED,
        )
        // Both are inherited `public static final int` fields declared
        // directly on `Connection`; Kotlin resolves an unqualified static
        // reference from a Java superclass the same way Java itself does.
        connectionProperties = PROPERTY_SELF_MANAGED
        connectionCapabilities = CAPABILITY_MUTE
        setAudioModeIsVoip(true)
    }

    /**
     * The call was answered - either [CallActionReceiver]'s own Answer
     * action calling this directly, or Telecom itself driving it (a paired
     * Bluetooth headset's own answer button, say). Both paths need the same
     * three things: Telecom told the call connected, then immediately ended
     * (see the class doc for why), and the app opened, since there is
     * nothing further either path could do.
     */
    override fun onAnswer() {
        setActive()
        end(DisconnectCause.LOCAL)
        context.startActivity(IncomingCallNotifier.openAppIntent(context))
    }

    /** [CallActionReceiver]'s own Decline action, or Telecom driving a reject directly, converge on the same state transition. */
    override fun onReject() {
        end(DisconnectCause.REJECTED)
    }

    /** Telecom ending this call through any path neither of the above already covers. */
    override fun onDisconnect() {
        end(DisconnectCause.LOCAL)
    }

    private fun end(reason: Int) {
        setDisconnected(DisconnectCause(reason))
        destroy()
        registry.remove(callId)
        NotificationManagerCompat.from(context)
            .cancel(IncomingCallNotifier.notificationIdFor(callId))
    }

    companion object {
        const val EXTRA_CALL_ID = "top.npcserver.slimm.extra.CALL_ID"
        const val EXTRA_CALLER_NAME = "top.npcserver.slimm.extra.CALLER_NAME"
        private const val ADDRESS_SCHEME = "slimm-call"

        /**
         * Reachable from [CallActionReceiver], the only other class that
         * needs to drive a live connection's state from outside Telecom's
         * own callbacks. A plain in-memory map, scoped to this process: a
         * call notification and its Telecom connection cannot outlive the
         * process either, since nothing here persists across a restart.
         */
        val registry = mutableMapOf<String, SlimmConnection>()
    }
}
