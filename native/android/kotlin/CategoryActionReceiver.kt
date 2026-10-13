package com.expensetracker.expense_tracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONObject

/** Handles a category button on the payment notification, without opening the app. */
class CategoryActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val eventId = intent.getStringExtra(PaymentNotifier.EXTRA_EVENT_ID) ?: return
        val categoryId = intent.getStringExtra(PaymentNotifier.EXTRA_CATEGORY_ID) ?: return
        val name = intent.getStringExtra(PaymentNotifier.EXTRA_CATEGORY_NAME) ?: "category"

        EventStore(context).upsert(
            JSONObject().put("id", eventId).put("categoryId", categoryId),
        )
        PaymentNotifier.showSaved(context, eventId, name)
        PaymentEvents.notifyListeners()
    }
}
