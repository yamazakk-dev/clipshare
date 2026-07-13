package com.ymac.clipshare.core

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ClipMessageTest {
    @Test
    fun authEncodeDecodeRoundTrip() {
        assertRoundTrip(
            ClipMessage.Auth(
                token = "shared-token",
                deviceId = DeviceId.ANDROID,
            ),
        )
    }

    @Test
    fun authOkEncodeDecodeRoundTrip() {
        assertRoundTrip(ClipMessage.AuthOk)
    }

    @Test
    fun clipEncodeDecodeRoundTrip() {
        assertRoundTrip(
            ClipMessage.Clip(
                text = "改行や引用符も同期する\n\"ClipShare\"",
                deviceId = DeviceId.MAC,
                ts = 1_752_400_000L,
            ),
        )
    }

    @Test
    fun clipWith64BitTimestampEncodeDecodeRoundTrip() {
        assertRoundTrip(
            ClipMessage.Clip(
                text = "64-bit timestamp",
                deviceId = DeviceId.MAC,
                ts = 3_000_000_000L,
            ),
        )
    }

    @Test
    fun encodedMessagesUseProtocolFieldNames() {
        val auth = JSONObject(
            ClipMessage.Auth("secret", DeviceId.ANDROID).encode(),
        )
        assertEquals(setOf("type", "token", "deviceId"), auth.keys().asSequence().toSet())
        assertEquals("auth", auth.getString("type"))
        assertEquals("secret", auth.getString("token"))
        assertEquals("android", auth.getString("deviceId"))

        val authOk = JSONObject(ClipMessage.AuthOk.encode())
        assertEquals(1, authOk.length())
        assertEquals("auth_ok", authOk.getString("type"))

        val clip = JSONObject(
            ClipMessage.Clip("hello", DeviceId.MAC, 123L).encode(),
        )
        assertEquals(setOf("type", "text", "deviceId", "ts"), clip.keys().asSequence().toSet())
        assertEquals("clip", clip.getString("type"))
        assertEquals("hello", clip.getString("text"))
        assertEquals("mac", clip.getString("deviceId"))
        assertEquals(123L, clip.getLong("ts"))
    }

    @Test
    fun protocolClipJsonDecodes() {
        assertEquals(
            ClipMessage.Clip("hello", DeviceId.ANDROID, 123L),
            ClipMessage.decode(
                """{"type":"clip","text":"hello","deviceId":"android","ts":123}""",
            ),
        )
    }

    @Test
    fun malformedJsonDecodesToNull() {
        assertNull(ClipMessage.decode("{not-json}"))
        assertNull(ClipMessage.decode("[]"))
        assertNull(ClipMessage.decode("""{"type":"auth_ok"} trailing"""))
        assertNull(
            ClipMessage.decode(
                """{"type":"auth_ok"}{"type":"auth_ok"}""",
            ),
        )
    }

    @Test
    fun unknownTypeDecodesToNull() {
        assertNull(ClipMessage.decode("""{"type":"unknown"}"""))
    }

    @Test
    fun missingRequiredFieldsDecodeToNull() {
        assertNull(
            ClipMessage.decode(
                """{"type":"auth","deviceId":"android"}""",
            ),
        )
        assertNull(
            ClipMessage.decode(
                """{"type":"clip","text":"hello","deviceId":"mac"}""",
            ),
        )
    }

    @Test
    fun requiredFieldsWithWrongTypesDecodeToNull() {
        val invalidMessages = listOf(
            """{"type":123,"token":"secret","deviceId":"android"}""",
            """{"type":"auth","token":123,"deviceId":"android"}""",
            """{"type":"auth","token":"secret","deviceId":123}""",
            """{"type":"clip","text":123,"deviceId":"mac","ts":123}""",
            """{"type":"clip","text":"hello","deviceId":"mac","ts":"123"}""",
            """{"type":"clip","text":"hello","deviceId":"mac","ts":true}""",
            """{"type":"clip","text":"hello","deviceId":"mac","ts":123.0}""",
        )

        invalidMessages.forEach { json ->
            assertNull(json, ClipMessage.decode(json))
        }
    }

    @Test
    fun invalidDeviceIdDecodesToNull() {
        assertNull(
            ClipMessage.decode(
                """{"type":"clip","text":"hello","deviceId":"ios","ts":123}""",
            ),
        )
    }

    @Test
    fun unknownAdditionalFieldsAreIgnored() {
        assertEquals(
            ClipMessage.Auth("secret", DeviceId.ANDROID),
            ClipMessage.decode(
                """{"type":"auth","token":"secret","deviceId":"android","futureField":true}""",
            ),
        )
        assertEquals(
            ClipMessage.AuthOk,
            ClipMessage.decode(
                """{"type":"auth_ok","futureField":true}""",
            ),
        )
        assertEquals(
            ClipMessage.Clip("hello", DeviceId.MAC, 123L),
            ClipMessage.decode(
                """{"type":"clip","text":"hello","deviceId":"mac","ts":123,"futureField":true}""",
            ),
        )
    }

    private fun assertRoundTrip(message: ClipMessage) {
        assertEquals(message, ClipMessage.decode(message.encode()))
    }
}
