package com.argusromtoolkit.argus

import android.app.Activity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ArgusQualificationBridgeTest {
    @Test
    fun staleActivityDetachCannotClearTheCurrentAttachment() {
        val bridge = ArgusQualificationBridge(RecordingMessenger())
        val first = TestActivity()
        val second = TestActivity()

        bridge.attachActivity(first, "activity-first")
        bridge.attachActivity(second, "activity-second")
        bridge.detachActivity(first)

        val result = RecordingResult()
        bridge.onMethodCall(MethodCall("readActivityInstanceId", null), result)

        assertEquals("activity-second", result.successValue)
        assertNull(result.errorCode)
    }

    @Test
    fun detachedActivityIdentityUsesTheBoundedErrorContract() {
        val bridge = ArgusQualificationBridge(RecordingMessenger())
        val activity = TestActivity()
        bridge.attachActivity(activity, "activity-first")
        bridge.detachActivity(activity)

        val result = RecordingResult()
        bridge.onMethodCall(MethodCall("readActivityInstanceId", null), result)

        assertEquals("ACTIVITY_DETACHED", result.errorCode)
        assertEquals("No Activity instance is attached", result.errorMessage)
    }

    @Test
    fun executionHostControlsAreUnavailableWhenTheBridgeIsNotDebuggable() {
        val bridge = ArgusQualificationBridge(
            RecordingMessenger(),
            foregroundExecutionHost = ArgusForegroundExecutionHost({}, {}),
        )

        val result = RecordingResult()
        bridge.onMethodCall(
            MethodCall("rejectNextExecutionHostStart", null),
            result,
        )

        assertTrue(result.notImplemented)
        assertNull(result.successValue)
        assertNull(result.errorCode)
    }

    @Test
    fun debugBridgeDelegatesHostControlsWithoutOwningHostState() {
        val host = ArgusForegroundExecutionHost({}, {})
        val bridge = ArgusQualificationBridge(
            RecordingMessenger(),
            foregroundExecutionHost = host,
            isDebugBuild = true,
        )

        val reject = RecordingResult()
        bridge.onMethodCall(
            MethodCall("rejectNextExecutionHostStart", null),
            reject,
        )
        val acquisition = RecordingResult()
        host.acquireLibraryScanLease(acquisition)

        assertFalse(reject.notImplemented)
        assertNull(reject.errorCode)
        assertEquals(null, reject.successValue)
        assertEquals(
            ArgusForegroundExecutionHost.ERROR_FOREGROUND_SERVICE_UNAVAILABLE,
            acquisition.errorCode,
        )
    }

    private class TestActivity : Activity()

    private class RecordingMessenger : BinaryMessenger {
        override fun send(channel: String, message: ByteBuffer?) = Unit

        override fun send(
            channel: String,
            message: ByteBuffer?,
            callback: BinaryMessenger.BinaryReply?,
        ) {
            callback?.reply(null)
        }

        override fun setMessageHandler(
            channel: String,
            handler: BinaryMessenger.BinaryMessageHandler?,
        ) = Unit
    }

    private class RecordingResult : MethodChannel.Result {
        var successValue: Any? = null
        var errorCode: String? = null
        var errorMessage: String? = null
        var notImplemented = false

        override fun success(result: Any?) {
            successValue = result
        }

        override fun error(code: String, message: String?, details: Any?) {
            errorCode = code
            errorMessage = message
        }

        override fun notImplemented() {
            notImplemented = true
        }
    }
}
