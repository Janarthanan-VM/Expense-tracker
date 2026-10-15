package com.expensetracker.expense_tracker

import android.app.Notification
import android.content.ComponentName
import android.os.Build
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

/**
 * Reads notifications from UPI apps and SMS apps, picks out completed
 * payments and queues them for the app. Every other notification is ignored
 * and nothing about it is stored.
 */
class PaymentNotificationListener : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        try {
            handle(sbn)
        } catch (e: Exception) {
            Log.w(TAG, "Could not read a payment notification", e)
        }
    }

    private fun handle(sbn: StatusBarNotification) {
        val source = PaymentSources.byPackage[sbn.packageName] ?: return
        if (!EventStore(this).isEnabled()) return

        val n = sbn.notification ?: return
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        val extras = n.extras ?: return

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val body = latestText(extras)
        if (title.isBlank() && body.isBlank()) return

        if (source.isSms) {
            // The title is the sender; the message itself is the body. The same
            // SMS may also be read directly by SmsReceiver, so both share one
            // "already seen" key and the payment is counted once.
            PaymentIntake.handle(
                context = this,
                text = body,
                strict = true,
                kind = "sms",
                channel = PaymentIntake.CHANNEL_SMS_NOTIFICATION,
                label = PaymentSources.bankSenderLabel(title) ?: "Bank SMS",
                time = sbn.postTime,
                seenKey = PaymentIntake.SMS_SEEN_KEY,
            )
        } else {
            val text = "$title. $body"
            PaymentIntake.handle(
                context = this,
                text = text,
                strict = false,
                kind = "notification",
                channel = PaymentIntake.CHANNEL_APP,
                label = source.label,
                time = sbn.postTime,
                seenKey = sbn.packageName,
                // App notifications have no reference number, so two real
                // "₹10 paid to Chai Point" payments read the same. The app's
                // own timestamp tells a new payment from a re-post.
                seenText = "$text|${if (n.`when` > 0) n.`when` else sbn.postTime / 60_000}",
            )
        }
    }

    /** Android can unbind the listener (battery savers); ask to be bound again. */
    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                requestRebind(ComponentName(this, PaymentNotificationListener::class.java))
            } catch (e: Exception) {
                Log.w(TAG, "Could not ask to reconnect", e)
            }
        }
    }

    /** Messaging apps keep a conversation; take only the newest message. */
    @Suppress("DEPRECATION")
    private fun latestText(extras: Bundle): String {
        val messages = extras.getParcelableArray(Notification.EXTRA_MESSAGES)
        if (messages != null && messages.isNotEmpty()) {
            val last = messages.last()
            if (last is Bundle) {
                val t = last.getCharSequence("text")?.toString()
                if (!t.isNullOrBlank()) return t
            }
        }
        extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
            ?.takeIf { it.isNotBlank() }?.let { return it }
        return extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
    }

    companion object {
        private const val TAG = "PaymentListener"
    }
}
