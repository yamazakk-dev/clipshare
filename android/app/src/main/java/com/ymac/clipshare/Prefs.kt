package com.ymac.clipshare

import android.content.Context
import android.content.SharedPreferences

class Prefs(context: Context) {
    private val preferences: SharedPreferences =
        context.applicationContext.getSharedPreferences(FILE_NAME, Context.MODE_PRIVATE)

    var host: String
        get() = preferences.getString(KEY_HOST, DEFAULT_HOST)
            ?.takeIf { it.isNotBlank() }
            ?: DEFAULT_HOST
        set(value) {
            preferences.edit().putString(KEY_HOST, value.trim()).apply()
        }

    var port: Int
        get() = preferences.getInt(KEY_PORT, DEFAULT_PORT)
            .takeIf { it in 1..MAX_PORT }
            ?: DEFAULT_PORT
        set(value) {
            preferences.edit()
                .putInt(KEY_PORT, value.takeIf { it in 1..MAX_PORT } ?: DEFAULT_PORT)
                .apply()
        }

    var token: String
        get() = preferences.getString(KEY_TOKEN, "").orEmpty()
        set(value) {
            preferences.edit().putString(KEY_TOKEN, value).apply()
        }

    var serviceEnabled: Boolean
        get() = preferences.getBoolean(KEY_SERVICE_ENABLED, false)
        set(value) {
            preferences.edit().putBoolean(KEY_SERVICE_ENABLED, value).apply()
        }

    fun saveConnection(host: String, port: Int, token: String) {
        preferences.edit()
            .putString(KEY_HOST, host.trim())
            .putInt(KEY_PORT, port)
            .putString(KEY_TOKEN, token)
            .apply()
    }

    private companion object {
        const val FILE_NAME = "clipshare_preferences"
        const val KEY_HOST = "host"
        const val KEY_PORT = "port"
        const val KEY_TOKEN = "token"
        const val KEY_SERVICE_ENABLED = "service_enabled"
        const val DEFAULT_HOST = "ymac"
        const val DEFAULT_PORT = 4747
        const val MAX_PORT = 65_535
    }
}
