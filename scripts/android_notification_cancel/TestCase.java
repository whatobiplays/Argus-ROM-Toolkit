package junit.framework;

/**
 * Compile-only shim for the legacy UiAutomator SDK jar. The Android device
 * supplies the real JUnit implementation to the UiAutomator runner; this
 * source only supplies javac with the superclass symbol because the current
 * SDK no longer packages that class in its host-side jars.
 */
public class TestCase {
}
