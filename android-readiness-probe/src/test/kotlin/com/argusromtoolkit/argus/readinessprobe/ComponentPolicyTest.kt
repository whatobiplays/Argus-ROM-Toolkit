package com.argusromtoolkit.argus.readinessprobe

import android.content.ComponentName
import android.content.Intent
import android.net.LocalSocket
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [30])
class ComponentPolicyTest {
    private class TrackingSocket : LocalSocket() {
        var released = false
        override fun isClosed(): Boolean = throw UnsupportedOperationException()
        override fun close() { released = true }
    }

    @Test fun socketAdmissionUsesRegistrationAndKeepsCapacityAndShutdownGates() {
        val transport = AndroidPeerSocket(ProbeSession { 0L }) { }
        val first = TrackingSocket()
        val second = TrackingSocket()
        val overflow = TrackingSocket()
        val afterShutdown = TrackingSocket()
        try {
            assertTrue(transport.registerSocket(first))
            assertTrue(transport.registerSocket(second))
            assertFalse(transport.registerSocket(overflow))
            assertTrue(overflow.released)
            assertFalse(first.released)
            assertFalse(second.released)
        } finally {
            transport.close()
        }
        assertTrue(first.released)
        assertTrue(second.released)
        assertFalse(transport.registerSocket(afterShutdown))
        assertTrue(afterShutdown.released)
    }

    @Test fun launcherDiscardsUntrustedModeAndUid() {
        val app = RuntimeEnvironment.getApplication()
        val intent = Intent(app, LauncherActivity::class.java).putExtra("mode", "enforcing").putExtra("uid", 123)
        val activity = Robolectric.buildActivity(LauncherActivity::class.java, intent).create().get()
        val launched = shadowOf(activity).nextStartedActivity
        assertEquals(ComponentName(app, ProbeControlActivity::class.java), launched.component)
        assertNull(launched.extras)
    }
    @Test fun ownerControlsAreNotExported() {
        val app = RuntimeEnvironment.getApplication()
        val info = app.packageManager.getActivityInfo(ComponentName(app, ProbeControlActivity::class.java), 0)
        assertFalse(info.exported)
        assertTrue(app.packageManager.getActivityInfo(ComponentName(app, LauncherActivity::class.java), 0).exported)
    }
}
