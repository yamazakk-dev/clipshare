package com.ymac.clipshare

import android.Manifest
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast

class SettingsActivity : Activity() {
    private lateinit var prefs: Prefs
    private lateinit var connectionStatus: TextView
    private lateinit var hostInput: EditText
    private lateinit var portInput: EditText
    private lateinit var tokenInput: EditText
    private var receiverRegistered = false

    private val stateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == SyncService.ACTION_STATE_CHANGED) {
                refreshConnectionState(
                    intent.getBooleanExtra(SyncService.EXTRA_CONNECTED, false),
                )
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings)

        prefs = Prefs(this)
        connectionStatus = findViewById(R.id.connectionStatus)
        hostInput = findViewById(R.id.hostInput)
        portInput = findViewById(R.id.portInput)
        tokenInput = findViewById(R.id.tokenInput)

        hostInput.setText(prefs.host)
        portInput.setText(prefs.port.toString())
        tokenInput.setText(prefs.token)

        findViewById<Button>(R.id.saveButton).setOnClickListener {
            if (saveSettings(requireToken = false) && prefs.serviceEnabled) {
                SyncService.start(this)
            }
        }
        findViewById<Button>(R.id.startButton).setOnClickListener {
            if (saveSettings(requireToken = true)) {
                SyncService.start(this)
                refreshConnectionState(false)
            }
        }
        findViewById<Button>(R.id.stopButton).setOnClickListener {
            SyncService.stop(this)
            refreshConnectionState(false)
        }
        findViewById<Button>(R.id.batterySettingsButton).setOnClickListener {
            openBatteryOptimizationSettings()
        }

        requestNotificationPermissionIfNeeded()
    }

    override fun onStart() {
        super.onStart()
        registerStateReceiver()
        refreshConnectionState(SyncService.isConnected())
    }

    override fun onStop() {
        if (receiverRegistered) {
            unregisterReceiver(stateReceiver)
            receiverRegistered = false
        }
        super.onStop()
    }

    private fun saveSettings(requireToken: Boolean): Boolean {
        hostInput.error = null
        portInput.error = null
        tokenInput.error = null

        val host = hostInput.text.toString().trim()
        if (host.isEmpty()) {
            hostInput.error = getString(R.string.error_host_required)
            return false
        }

        val port = portInput.text.toString().toIntOrNull()
        if (port == null || port !in 1..65_535) {
            portInput.error = getString(R.string.error_invalid_port)
            return false
        }

        val token = tokenInput.text.toString()
        if (requireToken && token.isBlank()) {
            tokenInput.error = getString(R.string.error_token_required)
            return false
        }

        prefs.saveConnection(host = host, port = port, token = token)
        Toast.makeText(this, R.string.settings_saved, Toast.LENGTH_SHORT).show()
        return true
    }

    private fun refreshConnectionState(isConnected: Boolean) {
        connectionStatus.setText(
            when {
                !prefs.serviceEnabled -> R.string.connection_stopped
                isConnected -> R.string.connection_connected
                else -> R.string.connection_waiting
            },
        )
    }

    private fun registerStateReceiver() {
        val filter = IntentFilter(SyncService.ACTION_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(stateReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(stateReceiver, filter)
        }
        receiverRegistered = true
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST,
            )
        }
    }

    private fun openBatteryOptimizationSettings() {
        runCatching {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }.onFailure {
            Toast.makeText(
                this,
                R.string.battery_settings_unavailable,
                Toast.LENGTH_SHORT,
            ).show()
        }
    }

    private companion object {
        const val NOTIFICATION_PERMISSION_REQUEST = 100
    }
}
