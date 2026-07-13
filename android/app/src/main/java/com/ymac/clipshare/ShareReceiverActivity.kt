package com.ymac.clipshare

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.Toast

class ShareReceiverActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val text = intent
            .takeIf { it.action == Intent.ACTION_SEND && it.type == MIME_TEXT_PLAIN }
            ?.getCharSequenceExtra(Intent.EXTRA_TEXT)
            ?.toString()

        when {
            text.isNullOrEmpty() -> showToast(R.string.share_text_missing)
            Prefs(this).token.isBlank() -> showToast(R.string.share_token_missing)
            runCatching { SyncService.sendClip(applicationContext, text) }.isSuccess -> {
                showToast(
                    if (SyncService.isConnected()) {
                        R.string.share_sent
                    } else {
                        R.string.share_queued
                    },
                )
            }
            else -> showToast(R.string.share_send_failed)
        }

        finish()
    }

    private fun showToast(message: Int) {
        Toast.makeText(applicationContext, message, Toast.LENGTH_SHORT).show()
    }

    private companion object {
        const val MIME_TEXT_PLAIN = "text/plain"
    }
}
