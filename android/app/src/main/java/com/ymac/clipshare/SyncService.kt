package com.ymac.clipshare

import android.content.ClipData
import android.content.ClipboardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import com.ymac.clipshare.core.ClipMessage
import com.ymac.clipshare.core.DeviceId
import com.ymac.clipshare.core.LoopGuard
import com.ymac.clipshare.core.ReconnectBackoff
import java.lang.ref.WeakReference
import java.util.concurrent.TimeUnit
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener

class SyncService : Service() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val loopGuard = LoopGuard()

    private lateinit var prefs: Prefs
    private lateinit var clipboardManager: ClipboardManager
    private lateinit var connectivityManager: ConnectivityManager
    private lateinit var notificationManager: NotificationManager
    private lateinit var httpClient: OkHttpClient

    private var defaultNetwork: Network? = null
    private var networkCallbackRegistered = false
    private var webSocket: WebSocket? = null
    private var authenticated = false
    private var pendingClip: String? = null
    private var reconnectAttempt = 0
    private var reconnectRunnable: Runnable? = null
    private var authenticationTimeoutRunnable: Runnable? = null

    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            val networkChanged = defaultNetwork != network
            defaultNetwork = network
            if (networkChanged || webSocket == null) {
                connectImmediately(forceReconnect = networkChanged)
            }
        }

        override fun onLost(network: Network) {
            if (defaultNetwork != network) {
                return
            }
            defaultNetwork = null
            cancelReconnect()
            clearWebSocket(cancel = true)
            publishConnectionState(false)
        }
    }

    override fun onCreate() {
        super.onCreate()
        activeService = WeakReference(this)
        prefs = Prefs(this)
        clipboardManager = getSystemService(ClipboardManager::class.java)
        connectivityManager = getSystemService(ConnectivityManager::class.java)
        notificationManager = getSystemService(NotificationManager::class.java)
        httpClient = OkHttpClient.Builder()
            .pingInterval(30, TimeUnit.SECONDS)
            .build()

        createNotificationChannel()
        startForeground(
            NOTIFICATION_ID,
            buildNotification(isConnected = false),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
        )
        registerNetworkCallback()
        publishConnectionState(false)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                prefs.serviceEnabled = true
                connectImmediately(forceReconnect = true)
            }

            ACTION_SEND_CLIP -> {
                prefs.serviceEnabled = true
                intent.getStringExtra(EXTRA_CLIP_TEXT)?.let(::handleOutgoingText)
            }

            else -> {
                if (prefs.serviceEnabled) {
                    connectImmediately(forceReconnect = false)
                } else {
                    stopSelf()
                    return START_NOT_STICKY
                }
            }
        }

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        cancelReconnect()
        cancelAuthenticationTimeout()
        if (networkCallbackRegistered) {
            runCatching { connectivityManager.unregisterNetworkCallback(networkCallback) }
            networkCallbackRegistered = false
        }
        clearWebSocket(cancel = true)
        httpClient.dispatcher.executorService.shutdown()
        httpClient.connectionPool.evictAll()
        publishConnectionState(false)
        if (activeService?.get() === this) {
            activeService = null
        }
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private fun registerNetworkCallback() {
        defaultNetwork = connectivityManager.activeNetwork
        connectivityManager.registerDefaultNetworkCallback(networkCallback, mainHandler)
        networkCallbackRegistered = true
    }

    private fun connectImmediately(forceReconnect: Boolean) {
        cancelReconnect()
        if (!prefs.serviceEnabled || defaultNetwork == null) {
            return
        }

        if (forceReconnect) {
            clearWebSocket(cancel = true)
        }
        if (webSocket != null) {
            return
        }

        val request = try {
            Request.Builder()
                .url(webSocketUrl(prefs.host, prefs.port))
                .build()
        } catch (_: IllegalArgumentException) {
            scheduleReconnect()
            return
        }

        authenticated = false
        publishConnectionState(false)
        webSocket = httpClient.newWebSocket(request, createWebSocketListener())
    }

    private fun webSocketUrl(host: String, port: Int): String {
        val formattedHost = if (':' in host && !host.startsWith("[")) {
            "[$host]"
        } else {
            host
        }
        return "ws://$formattedHost:$port"
    }

    private fun createWebSocketListener(): WebSocketListener =
        object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                mainHandler.post {
                    if (webSocket !== this@SyncService.webSocket) {
                        webSocket.cancel()
                        return@post
                    }

                    val auth = ClipMessage.Auth(
                        token = prefs.token,
                        deviceId = DeviceId.ANDROID,
                    )
                    if (webSocket.send(auth.encode())) {
                        scheduleAuthenticationTimeout(webSocket)
                    } else {
                        handleWebSocketEnded(webSocket)
                    }
                }
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                mainHandler.post {
                    handleIncomingMessage(webSocket, text)
                }
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                webSocket.close(code, reason)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                mainHandler.post {
                    handleWebSocketEnded(webSocket)
                }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                mainHandler.post {
                    handleWebSocketEnded(webSocket)
                }
            }
        }

    private fun handleIncomingMessage(socket: WebSocket, json: String) {
        if (socket !== webSocket) {
            return
        }

        val message = ClipMessage.decode(json)
        if (message == null) {
            socket.close(CLOSE_PROTOCOL_ERROR, "Invalid message")
            return
        }

        if (!authenticated) {
            if (message !== ClipMessage.AuthOk) {
                socket.close(CLOSE_PROTOCOL_ERROR, "Authentication required")
                return
            }

            cancelAuthenticationTimeout()
            authenticated = true
            reconnectAttempt = 0
            publishConnectionState(true)
            flushPendingClip(socket)
            return
        }

        when (message) {
            is ClipMessage.Clip -> {
                loopGuard.recordReceived(message.text)
                clipboardManager.setPrimaryClip(
                    ClipData.newPlainText("ClipShare", message.text),
                )
            }

            else -> socket.close(CLOSE_PROTOCOL_ERROR, "Unexpected message")
        }
    }

    private fun enqueueClip(text: String) {
        mainHandler.post {
            handleOutgoingText(text)
        }
    }

    private fun handleOutgoingText(text: String) {
        if (!loopGuard.shouldSend(text)) {
            return
        }

        pendingClip = text
        val socket = webSocket
        if (authenticated && socket != null) {
            flushPendingClip(socket)
        } else if (socket == null) {
            connectImmediately(forceReconnect = false)
        }
    }

    private fun flushPendingClip(socket: WebSocket) {
        val text = pendingClip ?: return
        val message = ClipMessage.Clip(
            text = text,
            deviceId = DeviceId.ANDROID,
            ts = System.currentTimeMillis() / 1_000,
        )
        if (socket.send(message.encode())) {
            pendingClip = null
        } else {
            handleWebSocketEnded(socket)
        }
    }

    private fun scheduleAuthenticationTimeout(socket: WebSocket) {
        cancelAuthenticationTimeout()
        val timeout = Runnable {
            if (socket === webSocket && !authenticated) {
                socket.cancel()
                handleWebSocketEnded(socket)
            }
        }
        authenticationTimeoutRunnable = timeout
        mainHandler.postDelayed(timeout, AUTHENTICATION_TIMEOUT_MILLIS)
    }

    private fun cancelAuthenticationTimeout() {
        authenticationTimeoutRunnable?.let(mainHandler::removeCallbacks)
        authenticationTimeoutRunnable = null
    }

    private fun handleWebSocketEnded(socket: WebSocket) {
        if (socket !== webSocket) {
            return
        }

        cancelAuthenticationTimeout()
        webSocket = null
        authenticated = false
        publishConnectionState(false)
        scheduleReconnect()
    }

    private fun scheduleReconnect() {
        if (!prefs.serviceEnabled || defaultNetwork == null || reconnectRunnable != null) {
            return
        }

        val delay = ReconnectBackoff.delayMillis(reconnectAttempt)
        reconnectAttempt = (reconnectAttempt + 1).coerceAtMost(MAXIMUM_BACKOFF_ATTEMPT)
        val reconnect = Runnable {
            reconnectRunnable = null
            connectImmediately(forceReconnect = false)
        }
        reconnectRunnable = reconnect
        mainHandler.postDelayed(reconnect, delay)
    }

    private fun cancelReconnect() {
        reconnectRunnable?.let(mainHandler::removeCallbacks)
        reconnectRunnable = null
    }

    private fun clearWebSocket(cancel: Boolean) {
        cancelAuthenticationTimeout()
        val socket = webSocket
        webSocket = null
        authenticated = false
        if (cancel) {
            socket?.cancel()
        }
    }

    private fun publishConnectionState(isConnected: Boolean) {
        connectionState = isConnected
        notificationManager.notify(
            NOTIFICATION_ID,
            buildNotification(isConnected),
        )
        sendBroadcast(
            Intent(ACTION_STATE_CHANGED)
                .setPackage(packageName)
                .putExtra(EXTRA_CONNECTED, isConnected),
        )
    }

    private fun createNotificationChannel() {
        notificationManager.createNotificationChannel(
            NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                getString(R.string.notification_channel_name),
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
    }

    private fun buildNotification(isConnected: Boolean): Notification {
        val settingsIntent = Intent(this, SettingsActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            settingsIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val text = if (isConnected) {
            getString(R.string.notification_connected)
        } else {
            getString(R.string.notification_waiting)
        }

        return Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(text)
            .setContentIntent(pendingIntent)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOngoing(true)
            .build()
    }

    companion object {
        const val ACTION_STATE_CHANGED = "com.ymac.clipshare.action.STATE_CHANGED"
        const val EXTRA_CONNECTED = "connected"

        private const val ACTION_START = "com.ymac.clipshare.action.START"
        private const val ACTION_SEND_CLIP = "com.ymac.clipshare.action.SEND_CLIP"
        private const val EXTRA_CLIP_TEXT = "clip_text"
        private const val NOTIFICATION_CHANNEL_ID = "clipshare_sync"
        private const val NOTIFICATION_ID = 4747
        private const val CLOSE_PROTOCOL_ERROR = 1002
        private const val AUTHENTICATION_TIMEOUT_MILLIS = 5_000L
        private const val MAXIMUM_BACKOFF_ATTEMPT = 6

        @Volatile
        private var activeService: WeakReference<SyncService>? = null

        @Volatile
        private var connectionState = false

        fun start(context: Context) {
            val applicationContext = context.applicationContext
            Prefs(applicationContext).serviceEnabled = true
            applicationContext.startForegroundService(
                Intent(applicationContext, SyncService::class.java).setAction(ACTION_START),
            )
        }

        fun stop(context: Context) {
            val applicationContext = context.applicationContext
            Prefs(applicationContext).serviceEnabled = false
            applicationContext.stopService(Intent(applicationContext, SyncService::class.java))
            connectionState = false
        }

        fun sendClip(text: String) {
            activeService?.get()?.enqueueClip(text)
        }

        fun sendClip(context: Context, text: String) {
            val applicationContext = context.applicationContext
            Prefs(applicationContext).serviceEnabled = true
            applicationContext.startForegroundService(
                Intent(applicationContext, SyncService::class.java)
                    .setAction(ACTION_SEND_CLIP)
                    .putExtra(EXTRA_CLIP_TEXT, text),
            )
        }

        fun isConnected(): Boolean = connectionState
    }
}
