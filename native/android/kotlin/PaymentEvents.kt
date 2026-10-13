package com.expensetracker.expense_tracker

import android.os.Handler
import android.os.Looper

/** Lets a running app know that new payments were queued. */
object PaymentEvents {
    @Volatile
    var listener: (() -> Unit)? = null

    fun notifyListeners() {
        val l = listener ?: return
        Handler(Looper.getMainLooper()).post { l() }
    }
}
