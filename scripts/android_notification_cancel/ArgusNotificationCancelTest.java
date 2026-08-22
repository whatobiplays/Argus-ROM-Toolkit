package com.argusromtoolkit.androidharness;

import android.graphics.Rect;

import com.android.uiautomator.core.UiDevice;
import com.android.uiautomator.core.UiObject;
import com.android.uiautomator.core.UiSelector;
import com.android.uiautomator.testrunner.UiAutomatorTestCase;

/**
 * Finds and invokes the visible Cancel action on the Argus foreground
 * notification without waiting for a serialized XML hierarchy between the
 * row expansion and the action tap.
 *
 * <p>The test still uses the Android UIAutomator accessibility surface. It
 * does not call an application debug command, a bridge method, or a durable
 * Jobs mutation. The shell harness records the action bounds printed here and
 * keeps XML dumping as the bounded failure diagnostic.</p>
 */
public final class ArgusNotificationCancelTest extends UiAutomatorTestCase {
    private static final String SYSTEM_UI_PACKAGE = "com.android.systemui";
    private static final String SCAN_TEXT = "Scanning 1 library job(s)";
    private static final String CANCEL_RESOURCE_ID = "android:id/action0";

    public void testCancel() throws Exception {
        final UiDevice device = getUiDevice();
        device.openNotification();

        final UiObject scanText = new UiObject(
                new UiSelector()
                        .packageName(SYSTEM_UI_PACKAGE)
                        .text(SCAN_TEXT));
        if (!scanText.waitForExists(5_000L)) {
            throw new AssertionError(
                    "Argus foreground notification scan projection was not visible");
        }

        final Rect scanBounds = scanText.getVisibleBounds();
        final int scanCenterY = scanBounds.centerY();
        UiObject expandButton = null;
        Rect expandBounds = null;
        for (int instance = 0; instance < 16; instance++) {
            final UiObject candidate = new UiObject(
                    new UiSelector()
                            .packageName(SYSTEM_UI_PACKAGE)
                            .resourceId("android:id/expand_button")
                            .description("Expand")
                            .instance(instance));
            final boolean candidateExists = candidate.exists();
            if (!candidateExists) {
                continue;
            }
            final Rect candidateBounds = candidate.getVisibleBounds();
            if (candidateBounds.top <= scanCenterY && scanCenterY <= candidateBounds.bottom) {
                expandButton = candidate;
                expandBounds = candidateBounds;
                break;
            }
        }
        if (expandButton == null || expandBounds == null || !expandButton.click()) {
            throw new AssertionError("Could not expand the Argus foreground notification");
        }
        System.out.printf(
                "notification-expand-bounds=[%d,%d][%d,%d]%n",
                expandBounds.left,
                expandBounds.top,
                expandBounds.right,
                expandBounds.bottom);

        final UiObject cancel = new UiObject(
                new UiSelector()
                        .packageName(SYSTEM_UI_PACKAGE)
                        .resourceId(CANCEL_RESOURCE_ID)
                        .text("Cancel")
                        .clickable(true));
        if (!cancel.waitForExists(2_000L)) {
            device.dumpWindowHierarchy(
                    "/data/local/tmp/ArgusP02004NotificationUiAutomationFailure.xml");
            throw new AssertionError(
                    "Visible Argus foreground notification did not expose Cancel");
        }

        final Rect bounds = cancel.getVisibleBounds();
        System.out.printf(
                "notification-cancel-bounds=[%d,%d][%d,%d]%n",
                bounds.left,
                bounds.top,
                bounds.right,
                bounds.bottom);
        if (!cancel.click()) {
            throw new AssertionError("Android UIAutomator could not invoke Cancel");
        }
        System.out.println("notification-cancel-clicked");
    }
}
