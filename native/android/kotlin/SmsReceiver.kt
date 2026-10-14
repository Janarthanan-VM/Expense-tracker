package com.expensetracker.expense_tracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log

/**
 * Reads incoming bank SMS directly (needs the SMS permission), so payments
 * are recorded even when message notifications are muted or grouped.
 * Messages from normal phone numbers are ignored; only bank-style sender
 * IDs such as "AX-HDFCBK" are read, and only payment fields are kept.
 */
class SmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        try {
            val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
            // A long SMS arrives in several parts; join them per sender.
            parts.filterNotNull()
                .groupBy { it.originatingAddress.orEmpty() }
                .forEach { (sender, messages) ->
                    val bank = PaymentSources.bankSenderLabel(sender) ?: return@forEach
                    val body = messages.joinToString("") { it.messageBody.orEmpty() }
                    if (body.isBlank()) return@forEach
                    val sentAt = messages.first().timestampMillis
                    val time = if (sentAt > 0) sentAt else System.currentTimeMillis()
                    PaymentIntake.handle(
                        context = context,
                        text = body,
                        strict = true,
                        kind = "sms",
                        label = bank,
                        time = time,
                        seenKey = PaymentIntake.SMS_SEEN_KEY,
                        fixedId = PaymentIntake.smsId(sender, time, body),
                    )
                }
        } catch (e: Exception) {
            Log.w(TAG, "Could not read an SMS", e)
        }
    }

    companion object {
        private const val TAG = "SmsReceiver"
    }
}
