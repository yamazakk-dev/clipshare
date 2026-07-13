package com.ymac.clipshare.core

import java.security.MessageDigest

class LoopGuard {
    private val lock = Any()
    private var lastReceivedHash: ByteArray? = null

    fun recordReceived(text: String) {
        val hash = hash(text)
        synchronized(lock) {
            lastReceivedHash = hash
        }
    }

    fun shouldSend(text: String): Boolean {
        val bytes = text.toByteArray(Charsets.UTF_8)
        if (bytes.size > MAXIMUM_TEXT_BYTE_COUNT) {
            return false
        }

        val hash = sha256(bytes)
        return synchronized(lock) {
            val receivedHash = lastReceivedHash
            if (receivedHash == null || !hash.contentEquals(receivedHash)) {
                true
            } else {
                lastReceivedHash = null
                false
            }
        }
    }

    private fun hash(text: String): ByteArray =
        sha256(text.toByteArray(Charsets.UTF_8))

    private fun sha256(bytes: ByteArray): ByteArray =
        MessageDigest.getInstance("SHA-256").digest(bytes)

    private companion object {
        const val MAXIMUM_TEXT_BYTE_COUNT = 5 * 1024 * 1024
    }
}
