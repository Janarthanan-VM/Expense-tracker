package com.expensetracker.expense_tracker

import android.content.Context
import org.json.JSONObject
import java.security.MessageDigest
import java.util.UUID

/**
 * One path for every detected payment, whether it came from a UPI app
 * notification, an SMS app notification or the SMS itself: parse, merge
 * duplicates, queue it for the app and offer category buttons.
 */
object PaymentIntake {

    /** Keeps the same bank SMS from being counted twice when it arrives as
     *  the SMS itself and as the messages app's notification. */
    const val SMS_SEEN_KEY = "sms"

    /**
     * @param seenKey namespace for "already handled this exact text" checks.
     * @param fixedId id to use when this payment is new (stable ids let a
     *   later SMS import recognise payments that were already saved).
     * @return true if a payment was found and queued.
     */
    fun handle(
        context: Context,
        text: String,
        strict: Boolean,
        kind: String,
        label: String,
        time: Long,
        seenKey: String,
        fixedId: String? = null,
    ): Boolean {
        val store = EventStore(context)
        if (!store.isEnabled()) return false
        if (!store.markSeen(seenKey, text, time)) return false

        val parsed = UpiParser.parse(text, strict) ?: return false
        val source = labelWithAccount(label, parsed.account)

        val existingId = store.matchRecent(parsed.amountPaise, parsed.isDebit, parsed.upiRef, time)
        val id = existingId ?: fixedId ?: UUID.randomUUID().toString()

        store.upsert(toEvent(id, parsed, kind, source, time))

        if (existingId == null) {
            store.addRecent(id, parsed.amountPaise, parsed.isDebit, parsed.upiRef, time)
            PaymentNotifier.showDetected(context, id, parsed, source, store.hints(parsed.isDebit))
        }
        PaymentEvents.notifyListeners()
        return true
    }

    fun toEvent(id: String, p: ParsedPayment, kind: String, label: String, time: Long): JSONObject {
        val event = JSONObject()
            .put("id", id)
            .put("amountPaise", p.amountPaise)
            .put("isDebit", p.isDebit)
            .put("mode", p.mode)
            .put("source", kind)
            .put("app", label)
            .put("time", time)
        p.payeeName?.let { event.put("payeeName", it) }
        p.payeeVpa?.let { event.put("payeeVpa", it) }
        p.upiRef?.let { event.put("upiRef", it) }
        p.account?.let { event.put("account", it) }
        return event
    }

    /** "HDFCBK" + "1234" -> "HDFCBK ••1234". */
    fun labelWithAccount(label: String, account: String?): String =
        if (account.isNullOrBlank()) label else "$label ••$account"

    /** Same id for the same SMS whether it is caught live or imported later. */
    fun smsId(sender: String, sentAt: Long, body: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest("${sender.trim().uppercase()}|$sentAt|${body.trim()}".toByteArray())
        return "sms-" + digest.take(16).joinToString("") { "%02x".format(it) }
    }
}
