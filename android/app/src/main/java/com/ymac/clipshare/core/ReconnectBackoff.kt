package com.ymac.clipshare.core

object ReconnectBackoff {
    fun delayMillis(attempt: Int): Long {
        require(attempt >= 0) { "attempt must not be negative" }
        if (attempt >= MAXIMUM_EXPONENTIAL_ATTEMPT) {
            return MAXIMUM_DELAY_MILLIS
        }
        return INITIAL_DELAY_MILLIS shl attempt
    }

    private const val INITIAL_DELAY_MILLIS = 1_000L
    private const val MAXIMUM_DELAY_MILLIS = 60_000L
    private const val MAXIMUM_EXPONENTIAL_ATTEMPT = 6
}
