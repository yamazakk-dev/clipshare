package com.ymac.clipshare.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class ReconnectBackoffTest {
    @Test
    fun delayDoublesUntilSixtySecondMaximum() {
        val delays = (0..9).map(ReconnectBackoff::delayMillis)

        assertEquals(
            listOf(
                1_000L,
                2_000L,
                4_000L,
                8_000L,
                16_000L,
                32_000L,
                60_000L,
                60_000L,
                60_000L,
                60_000L,
            ),
            delays,
        )
    }

    @Test
    fun negativeAttemptIsRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            ReconnectBackoff.delayMillis(-1)
        }
    }
}
