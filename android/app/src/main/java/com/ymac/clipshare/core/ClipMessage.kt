package com.ymac.clipshare.core

import org.json.JSONException
import org.json.JSONTokener
import org.json.JSONObject

enum class DeviceId(val jsonValue: String) {
    MAC("mac"),
    ANDROID("android");

    companion object {
        fun fromJsonValue(value: String): DeviceId? =
            entries.firstOrNull { it.jsonValue == value }
    }
}

sealed class ClipMessage {
    data class Auth(
        val token: String,
        val deviceId: DeviceId,
    ) : ClipMessage()

    data object AuthOk : ClipMessage()

    data class Clip(
        val text: String,
        val deviceId: DeviceId,
        val ts: Long,
    ) : ClipMessage()

    fun encode(): String {
        val json = JSONObject()

        when (this) {
            is Auth -> json
                .put("type", "auth")
                .put("token", token)
                .put("deviceId", deviceId.jsonValue)

            AuthOk -> json.put("type", "auth_ok")

            is Clip -> json
                .put("type", "clip")
                .put("text", text)
                .put("deviceId", deviceId.jsonValue)
                .put("ts", ts)
        }

        return json.toString()
    }

    companion object {
        fun decode(json: String): ClipMessage? = try {
            val tokener = JSONTokener(json)
            val fields = tokener.nextValue()
            if (fields !is JSONObject || tokener.nextClean() != '\u0000') {
                null
            } else {
                when (val type = fields.requiredString("type")) {
                    "auth" -> decodeAuth(fields)
                    "auth_ok" -> AuthOk
                    "clip" -> decodeClip(fields)
                    else -> null
                }
            }
        } catch (_: JSONException) {
            null
        }

        private fun decodeAuth(fields: JSONObject): Auth? {
            val token = fields.requiredString("token") ?: return null
            val deviceId = fields.requiredDeviceId() ?: return null
            return Auth(token = token, deviceId = deviceId)
        }

        private fun decodeClip(fields: JSONObject): Clip? {
            val text = fields.requiredString("text") ?: return null
            val deviceId = fields.requiredDeviceId() ?: return null
            val ts = fields.requiredLong("ts") ?: return null
            return Clip(text = text, deviceId = deviceId, ts = ts)
        }

        private fun JSONObject.requiredDeviceId(): DeviceId? =
            requiredString("deviceId")?.let(DeviceId::fromJsonValue)

        private fun JSONObject.requiredString(name: String): String? =
            get(name) as? String

        private fun JSONObject.requiredLong(name: String): Long? =
            when (val value = get(name)) {
                is Int -> value.toLong()
                is Long -> value
                else -> null
            }
    }
}
