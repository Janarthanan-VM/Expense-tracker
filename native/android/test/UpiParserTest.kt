package com.expensetracker.expense_tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Sample messages written in the style of common Indian bank SMS and UPI app
 * notifications (numbers and names are made up).
 */
class UpiParserTest {

    private fun parse(text: String, strict: Boolean = false): ParsedPayment {
        val p = UpiParser.parse(text, strict)
        assertNotNull("Expected a payment in: $text", p)
        return p!!
    }

    @Test fun hdfcUpiDebit() {
        val p = parse(
            "Sent Rs.250.00 From HDFC Bank A/C *1234 To SRI KRISHNA STORES On 13/10/26 " +
                "Ref 428612345678 Not You? Call 18002586161/SMS BLOCK UPI to 7308080808",
            strict = true,
        )
        assertEquals(25000L, p.amountPaise)
        assertTrue(p.isDebit)
        assertEquals("Sri Krishna Stores", p.payeeName)
        assertEquals("428612345678", p.upiRef)
    }

    @Test fun sbiDebitWithoutCurrencySymbol() {
        val p = parse(
            "Dear UPI user A/C X1234 debited by 120.0 on date 13Oct26 trf to RAVI KUMAR " +
                "Refno 428698765432. If not u? call 1800111109. -SBI",
            strict = true,
        )
        assertEquals(12000L, p.amountPaise)
        assertTrue(p.isDebit)
        assertEquals("Ravi Kumar", p.payeeName)
        assertEquals("428698765432", p.upiRef)
    }

    @Test fun iciciDebitPayeeBeforeCredited() {
        val p = parse(
            "ICICI Bank Acct XX123 debited for Rs 500.00 on 13-Oct-26; PAYTM credited. " +
                "UPI:428611112222. Call 18002662 for dispute. SMS BLOCK 123 to 9215676766.",
            strict = true,
        )
        assertEquals(50000L, p.amountPaise)
        assertTrue(p.isDebit)
        assertEquals("Paytm", p.payeeName)
        assertEquals("428611112222", p.upiRef)
        assertEquals("upi", p.mode)
    }

    @Test fun axisUpiPathFormat() {
        val p = parse(
            "INR 1,200.00 debited A/c no. XX1234 13-10-26, 10:15:21 UPI/P2M/428633334444/AMAZON PAY " +
                "Not you? SMS BLOCKUPI Cust ID to 919951860002 Axis Bank",
            strict = true,
        )
        assertEquals(120000L, p.amountPaise)
        assertTrue(p.isDebit)
        assertEquals("Amazon Pay", p.payeeName)
        assertEquals("428633334444", p.upiRef)
    }

    @Test fun creditFromVpa() {
        val p = parse(
            "Received Rs.500.00 in your Kotak Bank A/c X1234 from ravi@okaxis on 13-10-26.UPI Ref:428655556666.",
            strict = true,
        )
        assertEquals(50000L, p.amountPaise)
        assertFalse(p.isDebit)
        assertNull(p.payeeName)
        assertEquals("ravi@okaxis", p.payeeVpa)
        assertEquals("428655556666", p.upiRef)
    }

    @Test fun creditLinkedVpa() {
        val p = parse(
            "Rs 1,000.00 credited to a/c XX1234 on 13-10-26 by a/c linked to VPA ravi@okicici (UPI Ref No 428677778888).",
            strict = true,
        )
        assertEquals(100000L, p.amountPaise)
        assertFalse(p.isDebit)
        assertEquals("ravi@okicici", p.payeeVpa)
        assertEquals("428677778888", p.upiRef)
    }

    @Test fun googlePayReceived() {
        val p = parse("₹200 received. Ravi Kumar paid you ₹200")
        assertEquals(20000L, p.amountPaise)
        assertFalse(p.isDebit)
        assertEquals("Ravi Kumar", p.payeeName)
    }

    @Test fun phonePePaid() {
        val p = parse("Paid ₹150 to Chai Point")
        assertEquals(15000L, p.amountPaise)
        assertTrue(p.isDebit)
        assertEquals("Chai Point", p.payeeName)
    }

    @Test fun cardSpendSkipsLimitAmount() {
        val p = parse(
            "Rs.899.00 spent on your SBI Credit Card ending 1234 at SWIGGY on 13/10/26. Avl Lmt Rs.45,000",
            strict = true,
        )
        assertEquals(89900L, p.amountPaise)
        assertTrue(p.isDebit)
        assertEquals("Swiggy", p.payeeName)
        assertEquals("card", p.mode)
    }

    @Test fun creditCardUsedIsDebit() {
        val p = parse("Your credit card ending 1234 was used for Rs 500 at Big Bazaar", strict = true)
        assertTrue(p.isDebit)
        assertEquals(50000L, p.amountPaise)
    }

    @Test fun balanceAmountIsSkipped() {
        val p = parse("Avl Bal Rs 5,000.00. Rs 300 debited from a/c XX12 by UPI", strict = true)
        assertEquals(30000L, p.amountPaise)
        assertTrue(p.isDebit)
    }

    @Test fun indianDigitGrouping() {
        val p = parse("Paid ₹1,00,000 to Landlord")
        assertEquals(10000000L, p.amountPaise)
    }

    @Test fun neftIsBankMode() {
        val p = parse("Rs 25,000 credited to your A/c XX99 via NEFT from ACME PVT LTD", strict = true)
        assertFalse(p.isDebit)
        assertEquals("bank", p.mode)
    }

    @Test fun ignoresOtp() {
        assertNull(UpiParser.parse("123456 is your OTP for transaction of Rs 500 at Amazon"))
    }

    @Test fun ignoresRequests() {
        assertNull(UpiParser.parse("Ravi requested ₹300 from you"))
    }

    @Test fun ignoresFailedPayments() {
        assertNull(UpiParser.parse("Payment of Rs 500 to Ravi failed. Money will not be debited"))
    }

    @Test fun ignoresDueReminders() {
        assertNull(UpiParser.parse("Your electricity bill of Rs 1,250 is due on 20 Oct", strict = true))
    }

    @Test fun strictIgnoresPersonalChat() {
        assertNull(UpiParser.parse("I paid Rs 200 to the auto guy", strict = true))
    }

    @Test fun ignoresTextWithoutAmount() {
        assertNull(UpiParser.parse("Your UPI PIN was changed successfully", strict = true))
    }

    @Test fun tidyNameKeepsMixedCase() {
        assertEquals("McDonald's", UpiParser.tidyName("McDonald's"))
        assertEquals("Big Bazaar", UpiParser.tidyName("BIG  BAZAAR"))
    }

    // ------------------------------------------------------------ account digits (v0.4.0)

    @Test fun readsAccountDigitsFromDebit() {
        val p = parse(
            "Sent Rs.250.00 From HDFC Bank A/C *1234 To SRI KRISHNA STORES On 13/10/26 Ref 428612345678",
            strict = true,
        )
        assertEquals("1234", p.account)
    }

    @Test fun readsAccountDigitsWithXPrefix() {
        val p = parse(
            "Dear UPI user A/C X5678 debited by 120.0 on date 13Oct26 trf to RAVI KUMAR Refno 428698765432",
            strict = true,
        )
        assertEquals("5678", p.account)
    }

    @Test fun readsAccountDigitsFromCredit() {
        val p = parse(
            "Rs 1,000.00 credited to a/c XX4321 on 13-10-26 by a/c linked to VPA ravi@okicici (UPI Ref No 428677778888).",
            strict = true,
        )
        assertFalse(p.isDebit)
        assertEquals("4321", p.account)
    }

    @Test fun readsCardEndingDigits() {
        val p = parse(
            "Rs.899.00 spent on your SBI Credit Card ending 9876 at SWIGGY on 13/10/26. Avl Lmt Rs.45,000",
            strict = true,
        )
        assertEquals("9876", p.account)
    }

    @Test fun accountNoWithDots() {
        val p = parse(
            "INR 1,200.00 debited A/c no. XX2468 13-10-26, 10:15:21 UPI/P2M/428633334444/AMAZON PAY",
            strict = true,
        )
        assertEquals("2468", p.account)
    }

    @Test fun noAccountInAppNotification() {
        assertNull(parse("Paid ₹150 to Chai Point").account)
    }

    @Test fun salaryCreditViaNeft() {
        val p = parse(
            "Your A/c XX1111 is credited with INR 45,000.00 on 01-10-26 by NEFT from ACME PVT LTD. Avl Bal INR 52,300.00",
            strict = true,
        )
        assertFalse(p.isDebit)
        assertEquals(4500000L, p.amountPaise)
        assertEquals("bank", p.mode)
        assertEquals("1111", p.account)
    }

    @Test fun atmWithdrawalIsDebit() {
        val p = parse(
            "Rs.2000.00 withdrawn at ATM from A/c XX3333 on 13-10-26. Avl Bal Rs.8,000.00",
            strict = true,
        )
        assertTrue(p.isDebit)
        assertEquals(200000L, p.amountPaise)
    }

    // ------------------------------------------------------------ Union Bank (real formats, v0.5.2)

    @Test fun unionBankDebitWithColonAmountAndFavouring() {
        val p = parse(
            "Union Bank of India A/c *1094 Debited Rs:1.00 on 15-10-2026 08:40:24 by Mob Bk ref no " +
                "131306780290, Fvg: V SABARE Avl Bal Rs:1047.49. Not you?Call 18002333/SMS BLOCK 1094 to 8879365472",
            strict = true,
        )
        assertEquals(100L, p.amountPaise)
        assertTrue(p.isDebit)
        assertEquals("V Sabare", p.payeeName)
        assertEquals("131306780290", p.upiRef)
        assertEquals("1094", p.account)
    }

    @Test fun unionBankCreditWithOtpSafetyFooter() {
        val p = parse(
            "A/c *1094 Credited for Rs:1.00 on 15-10-2026 08:42:02 by Mob Bk ref no 665472310076 " +
                "Avl Bal Rs:1048.49.Never Share OTP/PIN/CVV-Union Bank of India",
            strict = true,
        )
        assertEquals(100L, p.amountPaise)
        assertFalse(p.isDebit)
        assertNull(p.payeeName)
        assertEquals("665472310076", p.upiRef)
        assertEquals("1094", p.account)
    }

    @Test fun doNotShareFooterIsNotAnOtpMessage() {
        val p = parse(
            "Rs 450.00 debited from A/c XX7788 to VPA shop@okaxis UPI Ref 428600001111. Do not share your OTP with anyone.",
            strict = true,
        )
        assertEquals(45000L, p.amountPaise)
        assertTrue(p.isDebit)
    }

    @Test fun realOtpMessageIsStillIgnored() {
        assertNull(UpiParser.parse("482913 is the OTP for your transaction of Rs:2,000.00 on A/c *1094", strict = true))
    }

    @Test fun inrWithColon() {
        assertEquals(125000L, parse("INR:1,250.00 debited from A/c XX12 via UPI Ref 428611110000", strict = true).amountPaise)
    }

    // ------------------------------------------------------------ more banks (v0.6.0)

    @Test fun canaraDebited() {
        val p = parse(
            "An amount of INR 150.00 has been DEBITED to your account XXX1234 on 15/10/2026 towards UPI. " +
                "Total Avail.bal INR 1,000.00 - Canara Bank",
            strict = true,
        )
        assertEquals(15000L, p.amountPaise)
        assertTrue(p.isDebit)
        assertEquals("1234", p.account)
    }

    @Test fun pnbDebitWithUpiColonRef() {
        val p = parse(
            "A/c XX1234 debited INR 200.00 Dt 15-10-26 13:01 thru UPI:428612340000.Bal INR 5,000.00 " +
                "Not u?Fwd this SMS to 9264092640 to block UPI.-PNB",
            strict = true,
        )
        assertEquals(20000L, p.amountPaise)
        assertTrue(p.isDebit)
        assertEquals("428612340000", p.upiRef)
    }

    @Test fun kotakSentToVpa() {
        val p = parse(
            "Sent Rs.10.00 from Kotak Bank AC X1234 to shop@ybl on 15-10-26.UPI Ref 428600002222. " +
                "Not you, https://kotak.com/KBANKT/Fraud",
            strict = true,
        )
        assertEquals(1000L, p.amountPaise)
        assertTrue(p.isDebit)
        assertEquals("shop@ybl", p.payeeVpa)
        assertEquals("428600002222", p.upiRef)
    }

    @Test fun indianBankCreditFromVpa() {
        val p = parse(
            "Your a/c no. XXXXXXXX1234 is credited by Rs.500.00 on 15-10-26 by a/c linked to VPA " +
                "friend@okhdfcbank (UPI Ref no 428699990000).",
            strict = true,
        )
        assertEquals(50000L, p.amountPaise)
        assertFalse(p.isDebit)
        assertEquals("friend@okhdfcbank", p.payeeVpa)
        assertEquals("1234", p.account)
    }

    @Test fun paytmBankSentToName() {
        val p = parse(
            "Rs.50 sent to ABC STORE from Paytm Payments Bank a/c 91XXXX1234. UPI Ref: 428611113333.",
            strict = true,
        )
        assertEquals(5000L, p.amountPaise)
        assertTrue(p.isDebit)
        assertEquals("Abc Store", p.payeeName)
    }

    @Test fun hdfcCreditCardSpend() {
        val p = parse(
            "Rs.1,299.00 spent on HDFC Bank Card x1234 at AMAZON on 2026-10-15:13:00:01. Avl Lmt: Rs.50,000.00",
            strict = true,
        )
        assertEquals(129900L, p.amountPaise)
        assertTrue(p.isDebit)
        assertEquals("card", p.mode)
        assertEquals("Amazon", p.payeeName)
    }

    // ------------------------------------------------------------ Google Pay phrasing (v0.7.0)

    @Test fun youPaid() {
        val p = parse("You paid ₹10 to Ravi Kumar")
        assertTrue(p.isDebit)
        assertEquals(1000L, p.amountPaise)
        assertEquals("Ravi Kumar", p.payeeName)
    }

    @Test fun paidToBankAccount() {
        val p = parse("Paid ₹1,000 to Ravi Kumar's bank account")
        assertTrue(p.isDebit)
        assertEquals(100000L, p.amountPaise)
        assertEquals("Ravi Kumar", p.payeeName)
    }

    @Test fun receivedFrom() {
        val p = parse("₹200 received from Ravi Kumar")
        assertFalse(p.isDebit)
        assertEquals("Ravi Kumar", p.payeeName)
    }

    @Test fun paymentToWasSuccessful() {
        val p = parse("Payment to Chai Point of ₹150 was successful")
        assertTrue(p.isDebit)
        assertEquals(15000L, p.amountPaise)
        assertEquals("Chai Point", p.payeeName)
    }

    @Test fun otpMessagesAreSensitive() {
        assertTrue(UpiParser.isSensitive("482913 is your OTP for a transaction of Rs 500"))
        assertTrue(UpiParser.isSensitive("Use UPI PIN only to send money"))
        assertFalse(UpiParser.isSensitive("A/c *1094 Credited for Rs:1.00. Never Share OTP/PIN/CVV-Union Bank of India"))
    }

    @Test fun mentionsMoney() {
        assertTrue(UpiParser.mentionsMoney("Get ₹50 cashback on your next bill"))
        assertFalse(UpiParser.mentionsMoney("Your weekly rewards are ready"))
    }
}
