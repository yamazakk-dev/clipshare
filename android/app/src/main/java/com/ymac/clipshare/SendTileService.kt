package com.ymac.clipshare

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

class SendTileService : TileService() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var listening = false

    override fun onStartListening() {
        super.onStartListening()
        listening = true
        showConnectionState()
    }

    override fun onStopListening() {
        listening = false
        mainHandler.removeCallbacksAndMessages(null)
        super.onStopListening()
    }

    override fun onClick() {
        super.onClick()
        showTileState(Tile.STATE_ACTIVE, getString(R.string.tile_sending_label))
        restoreConnectionStateLater()
        unlockAndRun {
            launchSendClipActivity()
        }
    }

    private fun launchSendClipActivity() {
        val intent = Intent(this, SendClipActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pendingIntent = PendingIntent.getActivity(
                this,
                SEND_CLIP_REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            startActivityAndCollapse(pendingIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    private fun restoreConnectionStateLater() {
        mainHandler.removeCallbacksAndMessages(null)
        mainHandler.postDelayed(::showConnectionState, FEEDBACK_DURATION_MILLIS)
    }

    private fun showConnectionState() {
        val connected = SyncService.isConnected()
        showTileState(
            if (connected) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE,
            getString(if (connected) R.string.tile_connected_label else R.string.tile_label),
        )
    }

    private fun showTileState(state: Int, label: String) {
        if (!listening) {
            return
        }
        qsTile?.apply {
            this.state = state
            this.label = label
            updateTile()
        }
    }

    override fun onDestroy() {
        mainHandler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    private companion object {
        const val FEEDBACK_DURATION_MILLIS = 1_500L
        const val SEND_CLIP_REQUEST_CODE = 4748
    }
}
