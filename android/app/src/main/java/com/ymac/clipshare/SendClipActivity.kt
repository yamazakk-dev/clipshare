package com.ymac.clipshare

import android.app.Activity
import android.content.ClipboardManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.Toast

class SendClipActivity : Activity() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var handled = false

    private val focusTimeout = Runnable {
        if (!handled) {
            handled = true
            showToast(R.string.tile_focus_unavailable)
            finish()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        mainHandler.postDelayed(focusTimeout, FOCUS_TIMEOUT_MILLIS)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus || handled) {
            return
        }

        handled = true
        mainHandler.removeCallbacks(focusTimeout)
        readClipboardAndSend()
    }

    private fun readClipboardAndSend() {
        val clipboard = getSystemService(ClipboardManager::class.java)
        val text = runCatching {
            clipboard.primaryClip
                ?.takeIf { it.itemCount > 0 }
                ?.getItemAt(0)
                ?.coerceToText(this)
                ?.toString()
        }.getOrNull()

        when {
            text.isNullOrEmpty() -> showToast(R.string.tile_clipboard_empty)
            Prefs(this).token.isBlank() -> showToast(R.string.tile_token_missing)
            else -> {
                val wasConnected = SyncService.isConnected()
                val accepted = runCatching {
                    SyncService.sendClip(applicationContext, text)
                }.isSuccess
                showToast(
                    when {
                        !accepted -> R.string.tile_send_failed
                        wasConnected -> R.string.tile_sent
                        else -> R.string.tile_queued
                    },
                )
            }
        }

        finish()
    }

    private fun showToast(message: Int) {
        Toast.makeText(applicationContext, message, Toast.LENGTH_SHORT).show()
    }

    override fun onDestroy() {
        mainHandler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    private companion object {
        const val FOCUS_TIMEOUT_MILLIS = 3_000L
    }
}
