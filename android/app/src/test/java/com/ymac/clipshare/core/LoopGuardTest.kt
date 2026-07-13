package com.ymac.clipshare.core

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LoopGuardTest {
    private val fiveMegabytes = 5 * 1024 * 1024

    @Test
    fun textCanBeSentBeforeAnythingIsReceived() {
        assertTrue(LoopGuard().shouldSend("local text"))
    }

    @Test
    fun receivedTextIsNotSentBack() {
        val guardUnderTest = LoopGuard()
        guardUnderTest.recordReceived("remote text")

        assertFalse(guardUnderTest.shouldSend("remote text"))
    }

    @Test
    fun receivedTextIsOnlySuppressedOnce() {
        val guardUnderTest = LoopGuard()
        guardUnderTest.recordReceived("remote text")

        assertFalse(guardUnderTest.shouldSend("remote text"))
        assertTrue(guardUnderTest.shouldSend("remote text"))
    }

    @Test
    fun differentTextCanBeSent() {
        val guardUnderTest = LoopGuard()
        guardUnderTest.recordReceived("remote text")

        assertTrue(guardUnderTest.shouldSend("different local text"))
    }

    @Test
    fun onlyMostRecentlyReceivedTextIsSuppressed() {
        val guardUnderTest = LoopGuard()
        guardUnderTest.recordReceived("first")
        guardUnderTest.recordReceived("second")

        assertTrue(guardUnderTest.shouldSend("first"))
        assertFalse(guardUnderTest.shouldSend("second"))
    }

    @Test
    fun exactlyFiveMegabytesCanBeSent() {
        val text = "a".repeat(fiveMegabytes)

        assertTrue(LoopGuard().shouldSend(text))
    }

    @Test
    fun moreThanFiveMegabytesCannotBeSent() {
        val text = "a".repeat(fiveMegabytes + 1)

        assertFalse(LoopGuard().shouldSend(text))
    }

    @Test
    fun sizeLimitCountsUtf8Bytes() {
        val text = "é".repeat((fiveMegabytes / 2) + 1)

        assertFalse(LoopGuard().shouldSend(text))
    }
}
