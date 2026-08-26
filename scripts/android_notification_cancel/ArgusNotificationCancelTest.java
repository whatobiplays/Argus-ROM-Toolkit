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
    private static final String SCAN_TEXT = "Library scan (1)";
    private static final String TITLE_TEXT = "Argus";
    private static final String TITLE_RESOURCE_ID = "android:id/title";
    private static final String EXPAND_RESOURCE_ID = "android:id/expand_button";
    private static final String CANCEL_RESOURCE_ID = "android:id/action0";
    private static final String NOTIFICATION_ROW_RESOURCE_ID =
            "com.android.systemui:id/expandableNotificationRow";
    private static final String NOTIFICATION_PERMISSION_ALLOW_RESOURCE_ID =
            "com.android.permissioncontroller:id/permission_allow_button";
    private static final long CANCEL_WAIT_MILLIS = 2_000L;
    private static final int MAX_UI_INSTANCES = 32;

    public void testCancel() throws Exception {
        final UiDevice device = getUiDevice();
        final UiObject notificationPermission = new UiObject(
                new UiSelector()
                        .resourceId(NOTIFICATION_PERMISSION_ALLOW_RESOURCE_ID)
                        .text("Allow")
                        .clickable(true));
        if (notificationPermission.waitForExists(2_000L) &&
                !notificationPermission.click()) {
            throw new AssertionError(
                    "Android notification permission prompt could not be dismissed");
        }
        device.openNotification();

        final UiObject scanText = new UiObject(
                new UiSelector()
                        .packageName(SYSTEM_UI_PACKAGE)
                        .text(SCAN_TEXT));
        if (!scanText.waitForExists(15_000L)) {
            throw new AssertionError(
                    "Argus foreground notification scan projection was not visible");
        }

        Rect rowBounds = findNotificationRowBounds(scanText);
        if (rowBounds == null) {
            failClosed(
                    device,
                    "Could not establish the Argus notification row for the expected scan text");
        }
        if (findControlWithinRow(
                        rowBounds,
                        TITLE_RESOURCE_ID,
                        TITLE_TEXT,
                        null,
                        false)
                == null) {
            failClosed(
                    device,
                    "Expected Argus notification title was not established in the scan row");
        }

        final UiObject cancel = findCancelInRow(device, scanText);
        rowBounds = findNotificationRowBounds(scanText);
        if (rowBounds == null) {
            failClosed(
                    device,
                    "Argus notification row disappeared while locating its Cancel action");
        }
        final UiObject expandButton = findControlWithinRow(
                rowBounds,
                EXPAND_RESOURCE_ID,
                null,
                "Expand",
                true);
        final UiObject collapseButton = findControlWithinRow(
                rowBounds,
                EXPAND_RESOURCE_ID,
                null,
                "Collapse",
                true);
        final NotificationCancelActionPlan.DisclosureState disclosureState =
                expandButton != null
                        ? NotificationCancelActionPlan.DisclosureState.EXPAND
                        : collapseButton != null
                                ? NotificationCancelActionPlan.DisclosureState.COLLAPSE
                                : NotificationCancelActionPlan.DisclosureState.UNAVAILABLE;
        final NotificationCancelActionPlan.Action action =
                NotificationCancelActionPlan.choose(cancel != null, disclosureState);
        System.out.printf(
                "notification-cancel-state=cancel-%s disclosure-%s%n",
                cancel == null ? "missing" : "actionable",
                disclosureState.name().toLowerCase());

        if (action == NotificationCancelActionPlan.Action.CLICK_CANCEL) {
            clickCancel(device, cancel);
            return;
        }
        if (action == NotificationCancelActionPlan.Action.EXPAND_THEN_CLICK) {
            final Rect expandBounds = expandButton.getVisibleBounds();
            if (!expandButton.click()) {
                failClosed(
                        device,
                        "Android UIAutomator could not invoke the Argus notification Expand action");
            }
            System.out.printf(
                    "notification-expand-bounds=[%d,%d][%d,%d]%n",
                    expandBounds.left,
                    expandBounds.top,
                    expandBounds.right,
                    expandBounds.bottom);
            final UiObject expandedCancel = findCancelInRow(device, scanText);
            if (expandedCancel == null) {
                failClosed(
                        device,
                        "Argus notification expanded but did not expose an actionable Cancel action");
            }
            clickCancel(device, expandedCancel);
            return;
        }
        failClosed(
                device,
                "Argus notification had no actionable Cancel action and no valid Expand path");
    }

    private static UiObject findCancelInRow(UiDevice device, UiObject scanText) throws Exception {
        final UiObject anyCancel = new UiObject(
                notificationSelector(CANCEL_RESOURCE_ID, "Cancel", null, true, -1));
        if (!anyCancel.waitForExists(CANCEL_WAIT_MILLIS)) {
            return null;
        }
        device.waitForIdle();
        final Rect rowBounds = findNotificationRowBounds(scanText);
        if (rowBounds == null) {
            return null;
        }
        return findControlWithinRow(
                rowBounds,
                CANCEL_RESOURCE_ID,
                "Cancel",
                null,
                true);
    }

    private static Rect findNotificationRowBounds(UiObject scanText) throws Exception {
        final Rect scanBounds = scanText.getVisibleBounds();
        for (int instance = 0; instance < MAX_UI_INSTANCES; instance++) {
            final UiObject row = new UiObject(
                    new UiSelector()
                            .packageName(SYSTEM_UI_PACKAGE)
                            .resourceId(NOTIFICATION_ROW_RESOURCE_ID)
                            .instance(instance));
            if (!row.exists()) {
                continue;
            }
            final Rect rowBounds = row.getVisibleBounds();
            if (contains(rowBounds, scanBounds)) {
                return rowBounds;
            }
        }
        return null;
    }

    private static UiObject findControlWithinRow(
            Rect rowBounds,
            String resourceId,
            String text,
            String description,
            boolean requireClickable) throws Exception {
        for (int instance = 0; instance < MAX_UI_INSTANCES; instance++) {
            final UiObject candidate = new UiObject(
                    notificationSelector(
                            resourceId,
                            text,
                            description,
                            requireClickable,
                            instance));
            if (!candidate.exists()) {
                continue;
            }
            final Rect candidateBounds = candidate.getVisibleBounds();
            if (contains(rowBounds, candidateBounds)) {
                return candidate;
            }
        }
        return null;
    }

    private static UiSelector notificationSelector(
            String resourceId,
            String text,
            String description,
            boolean requireClickable,
            int instance) {
        UiSelector selector = new UiSelector()
                .packageName(SYSTEM_UI_PACKAGE)
                .resourceId(resourceId);
        if (text != null) {
            selector = selector.text(text);
        }
        if (description != null) {
            selector = selector.description(description);
        }
        if (requireClickable) {
            selector = selector.clickable(true);
        }
        if (instance >= 0) {
            selector = selector.instance(instance);
        }
        return selector;
    }

    private static boolean contains(Rect outer, Rect inner) {
        return outer.left <= inner.left
                && outer.top <= inner.top
                && outer.right >= inner.right
                && outer.bottom >= inner.bottom;
    }

    private static void clickCancel(UiDevice device, UiObject cancel) throws Exception {
        final Rect bounds = cancel.getVisibleBounds();
        System.out.printf(
                "notification-cancel-bounds=[%d,%d][%d,%d]%n",
                bounds.left,
                bounds.top,
                bounds.right,
                bounds.bottom);
        if (!cancel.click()) {
            failClosed(device, "Android UIAutomator could not invoke the real notification Cancel action");
        }
        System.out.println("notification-cancel-clicked");
    }

    private static void failClosed(UiDevice device, String message) {
        device.dumpWindowHierarchy(
                "/data/local/tmp/ArgusP02004NotificationUiAutomationFailure.xml");
        throw new AssertionError(message);
    }
}
