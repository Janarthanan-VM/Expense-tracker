package com.expensetracker.expense_tracker

/** An app whose notifications we read. */
data class PaymentSource(
    val label: String,
    /** SMS apps carry bank messages; their text is parsed more strictly. */
    val isSms: Boolean,
)

object PaymentSources {
    val byPackage: Map<String, PaymentSource> = mapOf(
        // UPI apps
        "com.google.android.apps.nbu.paisa.user" to PaymentSource("Google Pay", false),
        "com.phonepe.app" to PaymentSource("PhonePe", false),
        "net.one97.paytm" to PaymentSource("Paytm", false),
        "in.org.npci.upiapp" to PaymentSource("BHIM", false),
        "com.dreamplug.androidapp" to PaymentSource("CRED", false),
        "in.amazon.mShop.android.shopping" to PaymentSource("Amazon Pay", false),
        "com.mobikwik_new" to PaymentSource("MobiKwik", false),
        // SMS apps (bank debit / credit messages)
        "com.google.android.apps.messaging" to PaymentSource("SMS", true),
        "com.samsung.android.messaging" to PaymentSource("SMS", true),
        "com.android.mms" to PaymentSource("SMS", true),
        "com.android.messaging" to PaymentSource("SMS", true),
        "com.oneplus.mms" to PaymentSource("SMS", true),
        "com.coloros.mms" to PaymentSource("SMS", true),
        "com.vivo.mms" to PaymentSource("SMS", true),
        "com.truecaller" to PaymentSource("SMS", true),
    )

    /** "AX-HDFCBK-S" -> "HDFCBK". Returns null for a normal contact name. */
    fun bankSenderLabel(title: String): String? {
        val t = title.trim().uppercase()
        val m = Regex("""^(?:[A-Z]{2}-)?([A-Z0-9]{4,9})(?:-[A-Z])?$""").find(t) ?: return null
        val code = m.groupValues[1]
        return if (code.any { it.isLetter() }) code else null
    }
}
