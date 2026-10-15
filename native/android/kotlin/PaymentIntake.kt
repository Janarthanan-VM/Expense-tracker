package com.expensetracker.expense_tracker

import android.content.Context
import org.json.JSONObject
import java.security.MessageDigest
import java.util.UUID

/** What happened to one message. Names are shown (translated) in the app. */
enum class Outcome(val key: String) {
    RECORDED("recorded"),
    MERGED("merged"),
    NOT_PAYMENT("not_payment"),
    ALREADY_SEEN("already_seen"),
    PAUSED("paused"),
    NOT_BANK("not_bank"),
}

/**
 * One path for every detected payment, whether it came from a UPI app
 * notification, an SMS app notification or the SMS itself: parse, merge
 * duplicates, queue it for the app and offer category buttons.
 */
object PaymentIntake {

    /** Keeps the same bank SMS from being counted twice when it arrives as
     *  the SMS itself and as the messages app's notification. */
    const val SMS_SEEN_KEY = "sms"

    /** Where a message came from; copies from different channels can merge. */
    const val CHANNEL_SMS = "sms"
    const val CHANNEL_SMS_NOTIFICATION = "sms_notification"
    const val CHANNEL_APP = "app_notification"

    /**
     * @param kind "sms" or "notification" (how the app labels the source).
     * @param seenKey namespace for "already handled this exact text" checks.
     * @param fixedId id to use when this payment is new (stable ids let a
     *   later SMS import recognise payments that were already saved).
     */
    fun handle(
        context: Context,
        text: String,
        strict: Boolean,
        kind: String,
        channel: String,
        label: String,
        time: Long,
        seenKey: String,
        fixedId: String? = null,
        seenText: String = text,
    ): Outcome = process(EventStore(context), context, text, strict, kind, channel, label, time, seenKey, fixedId, seenText)

    private fun process(
        store: EventStore,
        context: Context,
        text: String,
        strict: Boolean,
        kind: String,
        channel: String,
        label: String,
        time: Long,
        seenKey: String,
        fixedId: String?,
        seenText: String,
    ): Outcome {
        if (!store.isEnabled()) {
            store.recordCheck(channel, label, Outcome.PAUSED.key, time)
            return Outcome.PAUSED
        }
        if (!store.markSeen(seenKey, seenText, time)) {
            // The other copy of this message was already handled; not logged
            // again so the list shows one line per message.
            return Outcome.ALREADY_SEEN
        }

        val parsed = UpiParser.parse(text, strict)
        if (parsed == null) {
            // Payment apps post many notifications (offers, reminders); only
            // ones that mention an amount are worth a line in the list.
            if (channel != CHANNEL_APP || UpiParser.mentionsMoney(text)) {
                val keep = store.keepSkippedText() && !UpiParser.isSensitive(text)
                store.recordCheck(
                    channel, label, Outcome.NOT_PAYMENT.key, time,
                    text = if (keep) text else null,
                )
            }
            return Outcome.NOT_PAYMENT
        }
        val source = labelWithAccount(label, parsed.account)

        val existingId = store.matchRecent(parsed.amountPaise, parsed.isDebit, parsed.upiRef, time, channel)
        val id = existingId ?: fixedId ?: UUID.randomUUID().toString()

        store.upsert(toEvent(id, parsed, kind, source, time))

        val outcome = if (existingId == null) {
            store.addRecent(id, parsed.amountPaise, parsed.isDebit, parsed.upiRef, time, channel)
            PaymentNotifier.showDetected(context, id, parsed, source, store.hints(parsed.isDebit))
            Outcome.RECORDED
        } else {
            Outcome.MERGED
        }
        store.recordCheck(channel, source, outcome.key, time, parsed.amountPaise, parsed.isDebit)
        PaymentEvents.notifyListeners()
        return outcome
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
