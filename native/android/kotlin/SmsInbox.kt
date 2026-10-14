package com.expensetracker.expense_tracker

import android.content.Context
import android.provider.Telephony
import org.json.JSONArray

/**
 * Reads bank payment messages already in the SMS inbox, for the "Import
 * past bank SMS" button. Returns parsed payments only; message text is not
 * kept. No notifications are shown for imported payments.
 */
object SmsInbox {

    /** @return JSON array of payment events, oldest first. */
    fun readPayments(context: Context, sinceMillis: Long): String {
        val out = JSONArray()
        val projection = arrayOf(
            Telephony.Sms.ADDRESS,
            Telephony.Sms.BODY,
            Telephony.Sms.DATE,
            Telephony.Sms.DATE_SENT,
        )
        context.contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            projection,
            "${Telephony.Sms.DATE} >= ?",
            arrayOf(sinceMillis.toString()),
            "${Telephony.Sms.DATE} ASC",
        )?.use { c ->
            val iAddress = c.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
            val iBody = c.getColumnIndexOrThrow(Telephony.Sms.BODY)
            val iDate = c.getColumnIndexOrThrow(Telephony.Sms.DATE)
            val iSent = c.getColumnIndexOrThrow(Telephony.Sms.DATE_SENT)
            while (c.moveToNext()) {
                val sender = c.getString(iAddress) ?: continue
                val bank = PaymentSources.bankSenderLabel(sender) ?: continue
                val body = c.getString(iBody) ?: continue
                val parsed = UpiParser.parse(body, strict = true) ?: continue
                val received = c.getLong(iDate)
                val sentAt = c.getLong(iSent)
                val id = PaymentIntake.smsId(sender, if (sentAt > 0) sentAt else received, body)
                out.put(
                    PaymentIntake.toEvent(
                        id = id,
                        p = parsed,
                        kind = "sms",
                        label = PaymentIntake.labelWithAccount(bank, parsed.account),
                        time = if (sentAt > 0) sentAt else received,
                    ),
                )
            }
        }
        return out.toString()
    }
}
