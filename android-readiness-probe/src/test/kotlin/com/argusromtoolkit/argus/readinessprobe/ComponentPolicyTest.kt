package com.argusromtoolkit.argus.readinessprobe

import android.content.ComponentName
import android.content.Intent
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
