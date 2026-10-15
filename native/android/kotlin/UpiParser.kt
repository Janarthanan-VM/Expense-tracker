package com.expensetracker.expense_tracker

/**
 * A payment found in a notification or bank SMS.
 * [mode] is "upi", "card" or "bank" (matches PaymentMode names in Dart).
 */
data class ParsedPayment(
    val amountPaise: Long,
    val isDebit: Boolean,
    val payeeName: String?,
    val payeeVpa: String?,
    val upiRef: String?,
    val mode: String,
    /** Last digits of your bank account or card, e.g. "1234" from "A/c XX1234". */
    val account: String? = null,
)

/**
 * Reads amount, direction, payee, UPI ID and reference number from payment
 * notifications (Google Pay, PhonePe, ...) and bank SMS text.
 *
 * Pure Kotlin with no Android imports, so it is covered by plain unit tests.
 * Message formats differ between banks and change over time; anything that
 * is not clearly a completed payment returns null.
 */
object UpiParser {

    private val IC = setOf(RegexOption.IGNORE_CASE)

    /**
     * Safety footers such as "Never share OTP/PIN/CVV" or "Do not share your
     * OTP with anyone" are removed before the checks below, so a payment SMS
     * that merely warns about OTPs is not mistaken for an OTP message.
     */
    private val SAFETY_FOOTER = Regex(
        """\b(?:never|do\s*n[o']?t|pls\s+do\s+not|please\s+do\s+not)\s+share\b[^.\n]*""",
        IC,
    )

    /** Not a completed payment: OTPs, requests, failures, reminders, offers. */
    private val IGNORE = Regex(
        """\b(otp|one time password|verification code|requested|requesting|request|collect|failed|failure|declined|unsuccessful|cancelled|canceled|insufficient|pending|reversed|reminder|is due|due on|due date|will be debited|to be debited|scheduled|win|offer|cashback up ?to|get up ?to)\b""",
        IC,
    )

    /** "Rs.250", "Rs 250", "Rs:1.00" (Union Bank), "INR 1,200", "₹99". */
    private val CURRENCY_AMOUNT = Regex(
        """(?:₹|\bRs\.?|\bINR)\s*[:.]?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)""",
        IC,
    )

    /** SBI style: "debited by 120.0", "credited by 500". */
    private val WORD_AMOUNT = Regex(
        """\b(?:debited|credited)\s+(?:by|for|with)\s+(?:₹|Rs\.?|INR)?\s*[:.]?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)""",
        IC,
    )

    private val BALANCE_BEFORE = Regex("""(bal|balance|lmt|limit|avl|available)[^0-9]{0,6}$""", IC)

    private val DEBIT_WORDS = Regex(
        """\b(debited|debit(?!\s*card)|paid|sent|spent|transferred|withdrawn|purchase|payment of|used for|used at|dr)\b""",
        IC,
    )
    private val CREDIT_WORDS = Regex(
        """\b(credited|credit(?!\s*card)|received|deposited|added to|refund|refunded|cr)\b""",
        IC,
    )
    private val PAID_YOU = Regex("""\b(paid you|sent you|you received|you have received)\b""", IC)

    private val VPA = Regex("""\b([a-zA-Z0-9][a-zA-Z0-9._-]{1,}@[a-zA-Z][a-zA-Z0-9]{1,})\b""")

    private val REF = Regex(
        """\b(?:upi\s*ref(?:erence)?\s*(?:no\.?|number|id)?|upi\s*txn\s*id|txn\s*id|transaction\s*id|ref\s*no\.?|refno|ref|rrn|utr|upi)\s*[:.#/-]?\s*([0-9]{12})\b""",
        IC,
    )
    private val ANY_12_DIGITS = Regex("""(?<![0-9])([0-9]{12})(?![0-9])""")

    /** Axis / others: "UPI/P2M/428633334444/AMAZON PAY". */
    private val UPI_PATH_NAME = Regex("""\bUPI/[A-Z0-9]+/[0-9]{12}/([^/]+?)(?=/|\s+not\b|\s+call\b|\s*$)""", IC)

    private const val NAME = """([A-Za-z0-9][A-Za-z0-9 &.'_@-]{0,40}?)"""
    private const val NAME_END =
        """(?=\s+(?:on|via|from|ref|refno|upi|using|for|at|is|was|has|of|by|not|avl|info|in|with|and|dated|thru|through)\b|\s*[.,;:!(|]|\s+-|\s*$)"""

    /** Union Bank and others: "Fvg: V SABARE", "favouring ACME LTD". */
    private val FAVOURING_NAME = Regex("""\b(?:fvg|favou?ring|in\s+favou?r\s+of)\s*[:.-]?\s*$NAME$NAME_END""", IC)

    private val TO_NAME = Regex("""\b(?:trf\s+to|to|at)\s+(?:vpa\s+)?$NAME$NAME_END""", IC)
    private val FROM_NAME = Regex("""\b(?:from|by)\s+(?:vpa\s+)?$NAME$NAME_END""", IC)
    private val NAME_PAID_YOU = Regex("""([A-Z][A-Za-z .'&-]{1,40}?)\s+(?:paid|sent)\s+you\b""")
    private val NAME_CREDITED = Regex(""";\s*([A-Za-z0-9][A-Za-z0-9 &._-]{1,40}?)\s+credited\b""", IC)

    private val NOT_A_NAME = Regex(
        """^(your|you|a/c|ac|acct|account|xx|x+[0-9]|\*|the|bank|upi|card|my|me|vpa|mobile|mob|number|linked|self|net\s*banking|internet|neft|imps|rtgs|atm|cash|cheque|chq)\b""",
        IC,
    )

    /** "A/c XX1234", "Acct *123", "card ending 1234", "A/c no. 5678". */
    private val ACCOUNT = Regex(
        """\b(?:a/c|a/c\.|ac|acct|account|card)(?:\s*(?:no\.?|number|ending(?:\s+(?:with|in))?))?\s*[:.]?\s*(?:[x*.]+\s*)?([0-9]{3,6})\b""",
        IC,
    )

    /** Extra words a bank SMS must contain, so personal messages are ignored. */
    private val BANK_CUES = Regex("""\b(a/c|acct|account|upi|vpa|card|bank|neft|imps|rtgs|ref|txn)\b""", IC)

    /**
     * @param strict true for SMS (from messaging apps): require bank-like
     *   wording so chats such as "I paid Rs 200 to the auto" are ignored.
     */
    fun parse(raw: String, strict: Boolean = false): ParsedPayment? {
        val text = raw.replace(Regex("""\s+"""), " ").replace(SAFETY_FOOTER, " ").trim()
        if (text.isEmpty()) return null
        if (IGNORE.containsMatchIn(text)) return null
        if (strict && !BANK_CUES.containsMatchIn(text)) return null

        val amountPaise = findAmountPaise(text) ?: return null
        val isDebit = direction(text) ?: return null

        val vpa = VPA.find(text)?.groupValues?.get(1)
        var name = findName(text, isDebit)
        var payeeVpa = vpa
        if (name != null && name.contains('@')) {
            if (payeeVpa == null) payeeVpa = name
            name = null
        }

        return ParsedPayment(
            amountPaise = amountPaise,
            isDebit = isDebit,
            payeeName = name?.let(::tidyName),
            payeeVpa = payeeVpa?.lowercase(),
            upiRef = findRef(text),
            mode = mode(text),
            account = ACCOUNT.find(text)?.groupValues?.get(1),
        )
    }

    private fun findAmountPaise(text: String): Long? {
        for (m in CURRENCY_AMOUNT.findAll(text)) {
            val before = text.substring(maxOf(0, m.range.first - 14), m.range.first)
            if (BALANCE_BEFORE.containsMatchIn(before)) continue
            toPaise(m.groupValues[1])?.let { return it }
        }
        WORD_AMOUNT.find(text)?.let { return toPaise(it.groupValues[1]) }
        return null
    }

    private fun toPaise(number: String): Long? {
        val value = number.replace(",", "").toBigDecimalOrNull() ?: return null
        val paise = value.movePointRight(2).setScale(0, java.math.RoundingMode.HALF_UP).toLong()
        return if (paise in 1..1_000_000_000L) paise else null
    }

    /** true = money went out, false = came in, null = unclear. */
    private fun direction(text: String): Boolean? {
        if (PAID_YOU.containsMatchIn(text)) return false
        val debit = DEBIT_WORDS.find(text)?.range?.first
        val credit = CREDIT_WORDS.find(text)?.range?.first
        return when {
            debit == null && credit == null -> null
            credit == null -> true
            debit == null -> false
            else -> debit < credit
        }
    }

    private fun findName(text: String, isDebit: Boolean): String? {
        UPI_PATH_NAME.find(text)?.let { m -> accept(m.groupValues[1])?.let { return it } }
        if (!isDebit) {
            NAME_PAID_YOU.find(text)?.let { m -> accept(m.groupValues[1])?.let { return it } }
            for (m in FROM_NAME.findAll(text)) accept(m.groupValues[1])?.let { return it }
        } else {
            FAVOURING_NAME.find(text)?.let { m -> accept(m.groupValues[1])?.let { return it } }
            for (m in TO_NAME.findAll(text)) accept(m.groupValues[1])?.let { return it }
            NAME_CREDITED.find(text)?.let { m -> accept(m.groupValues[1])?.let { return it } }
        }
        return null
    }

    private fun accept(candidate: String): String? {
        val name = candidate.trim().trimEnd('.', '-', ',')
        if (name.length < 2) return null
        if (NOT_A_NAME.containsMatchIn(name)) return null
        if (name.all { it.isDigit() || it == ' ' || it == '-' || it == '/' }) return null
        if (CURRENCY_AMOUNT.containsMatchIn(name)) return null
        return name
    }

    private fun findRef(text: String): String? {
        REF.find(text)?.let { return it.groupValues[1] }
        if (Regex("""\bupi\b""", IC).containsMatchIn(text)) {
            return ANY_12_DIGITS.find(text)?.groupValues?.get(1)
        }
        return null
    }

    private fun mode(text: String): String {
        val lower = text.lowercase()
        return when {
            Regex("""\b(neft|imps|rtgs)\b""").containsMatchIn(lower) -> "bank"
            Regex("""\bupi\b|@""").containsMatchIn(lower) -> "upi"
            Regex("""\b(credit card|debit card|card)\b""").containsMatchIn(lower) -> "card"
            else -> "upi"
        }
    }

    /** "SRI KRISHNA STORES" -> "Sri Krishna Stores"; mixed case is kept. */
    fun tidyName(name: String): String {
        val collapsed = name.replace(Regex("""\s+"""), " ").trim()
        if (collapsed.any { it.isLowerCase() }) return collapsed
        return collapsed.split(' ').joinToString(" ") { word ->
            word.lowercase().replaceFirstChar { it.uppercaseChar() }
        }
    }
}
