package android.test;

/**
 * Compile/runtime compatibility shim for the API 36 legacy UiAutomator
 * runner. API 36's runner references this platform type even though the
 * corresponding SDK jars no longer package it. The notification test never
 * implements the marker, so the empty interface is sufficient.
 */
public interface RepetitiveTest {
}
