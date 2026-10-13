package com.expensetracker.expense_tracker

import android.app.Notification
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONObject
import java.util.UUID

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
        val store = EventStore(this)
        if (!store.isEnabled()) return

        val n = sbn.notification ?: return
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        val extras = n.extras ?: return

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val body = latestText(extras)
        if (title.isBlank() && body.isBlank()) return

        // For SMS the title is the sender; the message itself is the body.
        val text = if (source.isSms) body else "$title. $body"
        val now = sbn.postTime
        if (!store.markSeen(sbn.packageName, text, now)) return

        val parsed = UpiParser.parse(text, strict = source.isSms) ?: return

        val label = if (source.isSms) {
            PaymentSources.bankSenderLabel(title) ?: "Bank SMS"
        } else {
            source.label
        }

        val existingId = store.matchRecent(parsed.amountPaise, parsed.isDebit, parsed.upiRef, now)
        val id = existingId ?: UUID.randomUUID().toString()

        val event = JSONObject()
            .put("id", id)
            .put("amountPaise", parsed.amountPaise)
            .put("isDebit", parsed.isDebit)
            .put("mode", parsed.mode)
            .put("source", if (source.isSms) "sms" else "notification")
            .put("app", label)
            .put("time", now)
        parsed.payeeName?.let { event.put("payeeName", it) }
        parsed.payeeVpa?.let { event.put("payeeVpa", it) }
        parsed.upiRef?.let { event.put("upiRef", it) }
        store.upsert(event)

        if (existingId == null) {
            store.addRecent(id, parsed.amountPaise, parsed.isDebit, parsed.upiRef, now)
            PaymentNotifier.showDetected(this, id, parsed, label, store.hints(parsed.isDebit))
        }
        PaymentEvents.notifyListeners()
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
