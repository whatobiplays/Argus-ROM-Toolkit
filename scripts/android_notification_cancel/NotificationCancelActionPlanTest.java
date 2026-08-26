package com.argusromtoolkit.androidharness;

/**
 * Host-side regression coverage for the notification Cancel state machine.
 *
 * <p>Compile this class with {@code NotificationCancelActionPlan.java} and
 * run it with the standard JVM. Keeping the state decisions free of Android
 * framework types makes both supported notification presentations directly
 * testable without replacing the real UIAutomator interaction.</p>
 */
public final class NotificationCancelActionPlanTest {
    private NotificationCancelActionPlanTest() {
    }

    public static void main(String[] args) {
        expect(
                NotificationCancelActionPlan.Action.CLICK_CANCEL,
                NotificationCancelActionPlan.choose(
                        true,
                        NotificationCancelActionPlan.DisclosureState.COLLAPSE),
                "an already-expanded notification clicks visible Cancel directly");
        expect(
                NotificationCancelActionPlan.Action.EXPAND_THEN_CLICK,
                NotificationCancelActionPlan.choose(
                        false,
                        NotificationCancelActionPlan.DisclosureState.EXPAND),
                "a collapsed notification expands before clicking Cancel");
        expect(
                NotificationCancelActionPlan.Action.FAIL,
                NotificationCancelActionPlan.choose(
                        false,
                        NotificationCancelActionPlan.DisclosureState.COLLAPSE),
                "a collapsed action state cannot use Collapse as an expansion path");
        expect(
                NotificationCancelActionPlan.Action.FAIL,
                NotificationCancelActionPlan.choose(
                        false,
                        NotificationCancelActionPlan.DisclosureState.UNAVAILABLE),
                "missing notification action and disclosure fail closed");
        System.out.println("NotificationCancelActionPlanTest passed");
    }

    private static void expect(
            NotificationCancelActionPlan.Action expected,
            NotificationCancelActionPlan.Action actual,
            String description) {
        if (expected != actual) {
            throw new AssertionError(
                    description + ": expected " + expected + " but was " + actual);
        }
    }
}
