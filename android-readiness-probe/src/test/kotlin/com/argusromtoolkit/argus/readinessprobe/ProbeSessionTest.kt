package com.argusromtoolkit.argus.readinessprobe

import org.junit.Assert.*
import org.junit.Test

class ProbeSessionTest {
    private val id = "a".repeat(32)
    private val attempt = "b".repeat(32)
    private fun configured(clock: () -> Long = { 0L }) = ProbeSession(clock).apply { configure(id, "probe.test", this@ProbeSessionTest.attempt) }
    @Test fun discoveryNeverAutomaticallyAuthorizesPeer() {
        val s = configured(); s.armDiscovery(); s.observed(123)
        assertNull(s.pinnedUid)
        assertThrows(IllegalStateException::class.java) { s.enforce(123) }
    }
    @Test fun explicitCorrelationAndManualUidAreBothRequired() {
        val s = configured(); s.armDiscovery(); s.observed(123)
        s.confirm(id, attempt, true); s.enforce(123)
        assertEquals(123, s.pinnedUid)
        assertThrows(IllegalStateException::class.java) { s.enforce(123) }
    }
    @Test fun staleAndUncorrelatedConfirmationTerminatesSession() {
        for ((session, discovery, confirmed) in listOf(Triple("c".repeat(32), attempt, true), Triple(id, "c".repeat(32), true), Triple(id, attempt, false))) {
            val s = configured(); s.armDiscovery(); s.observed(123)
            assertThrows(IllegalStateException::class.java) { s.confirm(session, discovery, confirmed) }
            assertEquals(ProbeSession.Phase.CLOSED, s.phase)
        }
    }
    @Test fun wrongUidAndExpiredAuthorityTerminateSession() {
        var now = 0L
        val s = configured { now }; s.armDiscovery(); s.observed(123); s.confirm(id, attempt, true)
        assertThrows(IllegalStateException::class.java) { s.enforce(456) }
        assertEquals(ProbeSession.Phase.CLOSED, s.phase)
        val expired = configured { now }; now = 600001
        assertThrows(IllegalStateException::class.java) { expired.armDiscovery() }
    }
    @Test fun identitiesCannotBeReused() {
        val s = configured(); s.armDiscovery(); s.observed(123); s.confirm(id, attempt, true); s.enforce(123)
        val r = Request("c".repeat(32), "d".repeat(32), "e".repeat(32), 1)
        assertTrue(s.admit(r)); assertFalse(s.admit(r))
        s.close(); assertNull(s.pinnedUid)
        assertThrows(IllegalStateException::class.java) { s.armDiscovery() }
    }
}
