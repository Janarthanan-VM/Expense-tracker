package com.expensetracker.expense_tracker

import android.app.Notification
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
                label = PaymentSources.bankSenderLabel(title) ?: "Bank SMS",
                time = sbn.postTime,
                seenKey = PaymentIntake.SMS_SEEN_KEY,
            )
        } else {
            PaymentIntake.handle(
                context = this,
                text = "$title. $body",
                strict = false,
                kind = "notification",
                label = source.label,
                time = sbn.postTime,
                seenKey = sbn.packageName,
            )
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
