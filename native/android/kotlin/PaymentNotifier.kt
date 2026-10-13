package com.expensetracker.expense_tracker

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import java.text.NumberFormat
import java.util.Locale

/** Shows "₹250 paid to ..." with one-tap category buttons. */
object PaymentNotifier {

    private const val CHANNEL_ID = "detected_payments"
    const val EXTRA_EVENT_ID = "event_id"
    const val EXTRA_CATEGORY_ID = "category_id"
    const val EXTRA_CATEGORY_NAME = "category_name"
    const val ACTION_OPEN_EVENT = "com.expensetracker.OPEN_EVENT"

    fun notificationId(eventId: String) = eventId.hashCode()

    fun formatAmount(paise: Long): String {
        val f = NumberFormat.getCurrencyInstance(Locale("en", "IN"))
        if (paise % 100 == 0L) f.maximumFractionDigits = 0
        return f.format(paise / 100.0)
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Detected payments",
            NotificationManager.IMPORTANCE_DEFAULT,
        )
        channel.description = "Choose a category for UPI payments the app records"
        nm.createNotificationChannel(channel)
    }

    @Suppress("DEPRECATION")
    private fun builder(context: Context): Notification.Builder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            Notification.Builder(context)
        }

    private fun immutable(flags: Int) =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) flags or PendingIntent.FLAG_IMMUTABLE else flags

    private fun openAppIntent(context: Context, eventId: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_OPEN_EVENT
            putExtra(EXTRA_EVENT_ID, eventId)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(
            context, requestCode, intent, immutable(PendingIntent.FLAG_UPDATE_CURRENT),
        )
    }

    fun showDetected(
        context: Context,
        eventId: String,
        payment: ParsedPayment,
        appLabel: String,
        hints: List<Pair<String, String>>,
    ) {
        ensureChannel(context)
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val base = notificationId(eventId)

        val who = payment.payeeName ?: payment.payeeVpa
        val amount = formatAmount(payment.amountPaise)
        val title = when {
            payment.isDebit && who != null -> "$amount paid to $who"
            payment.isDebit -> "$amount paid"
            who != null -> "$amount received from $who"
            else -> "$amount received"
        }

        val b = builder(context)
            .setSmallIcon(R.drawable.ic_stat_payment)
            .setContentTitle(title)
            .setContentText("Choose a category ($appLabel)")
            .setContentIntent(openAppIntent(context, eventId, base * 4 + 3))
            .setAutoCancel(true)
            .setShowWhen(true)

        hints.take(2).forEachIndexed { i, (id, name) ->
            val intent = Intent(context, CategoryActionReceiver::class.java).apply {
                putExtra(EXTRA_EVENT_ID, eventId)
                putExtra(EXTRA_CATEGORY_ID, id)
                putExtra(EXTRA_CATEGORY_NAME, name)
            }
            val pi = PendingIntent.getBroadcast(
                context, base * 4 + i, intent, immutable(PendingIntent.FLAG_UPDATE_CURRENT),
            )
            b.addAction(Notification.Action.Builder(null, name, pi).build())
        }
        b.addAction(
            Notification.Action.Builder(null, "Other…", openAppIntent(context, eventId, base * 4 + 2)).build(),
        )

        try {
            nm.notify(base, b.build())
        } catch (e: SecurityException) {
            // Notification permission not granted; the payment is still queued.
        }
    }

    fun showSaved(context: Context, eventId: String, categoryName: String) {
        ensureChannel(context)
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val b = builder(context)
            .setSmallIcon(R.drawable.ic_stat_payment)
            .setContentTitle("Saved as $categoryName")
            .setContentText("Tap to change")
            .setContentIntent(openAppIntent(context, eventId, notificationId(eventId) * 4 + 3))
            .setAutoCancel(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) b.setTimeoutAfter(5000)
        try {
            nm.notify(notificationId(eventId), b.build())
        } catch (e: SecurityException) {
            // Ignore: nothing to update without permission.
        }
    }
}
