package com.expensetracker.expense_tracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PaymentIntakeTest {

    @Test fun smsIdIsStableForTheSameMessage() {
        val a = PaymentIntake.smsId("AX-HDFCBK", 1_760_000_000_000L, "Rs 250 debited from A/c XX1234")
        val b = PaymentIntake.smsId("ax-hdfcbk ", 1_760_000_000_000L, " Rs 250 debited from A/c XX1234 ")
        assertEquals(a, b)
        assertTrue(a.startsWith("sms-"))
        assertEquals(4 + 32, a.length)
    }

    @Test fun smsIdDiffersForDifferentMessages() {
        val base = PaymentIntake.smsId("AX-HDFCBK", 1L, "Rs 250 debited")
        assertNotEquals(base, PaymentIntake.smsId("AX-HDFCBK", 2L, "Rs 250 debited"))
        assertNotEquals(base, PaymentIntake.smsId("AX-SBIUPI", 1L, "Rs 250 debited"))
        assertNotEquals(base, PaymentIntake.smsId("AX-HDFCBK", 1L, "Rs 251 debited"))
    }

    @Test fun labelIncludesAccountDigits() {
        assertEquals("HDFCBK ••1234", PaymentIntake.labelWithAccount("HDFCBK", "1234"))
        assertEquals("HDFCBK", PaymentIntake.labelWithAccount("HDFCBK", null))
        assertEquals("Google Pay", PaymentIntake.labelWithAccount("Google Pay", ""))
    }

    @Test fun bankSenderIdsAreRecognised() {
        assertEquals("HDFCBK", PaymentSources.bankSenderLabel("AX-HDFCBK"))
        assertEquals("SBIUPI", PaymentSources.bankSenderLabel("VM-SBIUPI-S"))
        assertEquals("ICICIB", PaymentSources.bankSenderLabel("ICICIB"))
    }

    @Test fun phoneNumbersAreNotBanks() {
        assertEquals(null, PaymentSources.bankSenderLabel("+919876543210"))
        assertEquals(null, PaymentSources.bankSenderLabel("9876543210"))
    }
}
