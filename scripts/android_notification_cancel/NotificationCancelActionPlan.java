package com.argusromtoolkit.androidharness;

/**
 * Selects the only valid way to reach the foreground notification's Cancel
 * action from the state currently exposed by SystemUI.
 *
 * <p>The notification may be rendered expanded or collapsed. A visible
 * Collapse affordance is evidence that the row is already expanded; it is not
 * a reason to change the row's state before using an action that is already
 * available.</p>
 */
final class NotificationCancelActionPlan {
    enum DisclosureState {
        EXPAND,
        COLLAPSE,
        UNAVAILABLE
    }

    enum Action {
        CLICK_CANCEL,
        EXPAND_THEN_CLICK,
        FAIL
    }

    private NotificationCancelActionPlan() {
    }

    static Action choose(boolean cancelActionable, DisclosureState disclosureState) {
        if (cancelActionable) {
            return Action.CLICK_CANCEL;
        }
        if (disclosureState == DisclosureState.EXPAND) {
            return Action.EXPAND_THEN_CLICK;
        }
        return Action.FAIL;
    }
}
