package com.argusromtoolkit.argus.readinessprobe

import java.util.ArrayDeque
import org.junit.Assert.*
import org.junit.Test

class DiscoveryWindowTest {
    private class Peer(val uid: Int) : PeerConnection {
        var closed = false
        override fun peerUid() = uid
        override fun input(): java.io.InputStream = error("Discovery must not read")
        override fun output(): java.io.OutputStream = error("Discovery must not write")
        override fun close() { closed = true }
    }
    @Test fun queuedSecondPeerAtDeadlineCannotEstablishPolicy() {
        var clock = 0L
        val first = Peer(123)
        val queued = Peer(456)
        val backlog = ArrayDeque<Peer>().apply { add(first) }
        var polls = 0
        val window = DiscoveryWindow({ clock }, { _ ->
            polls++
            if (polls == 2) {
                // A wait expires concurrently with another completed connection.
                clock = 5000; backlog.add(queued); false
            } else backlog.isNotEmpty()
        }, { backlog.removeFirst() }, { true })
        assertThrows(DiscoveryRejected::class.java) { window.observe() }
        assertTrue(first.closed)
        assertTrue(queued.closed)
    }

    @Test fun onePeerRequiresEmptyTerminalQueueSnapshot() {
        var clock = 0L
        var finalPolls = 0
        val peer = Peer(123)
        var queued = true
        val result = DiscoveryWindow({ clock }, { timeout ->
            if (timeout == 0) finalPolls++
            clock += timeout
            queued
        }, { queued = false; peer }, { true }).observe()
        assertEquals(123, result.uid)
        assertEquals(5000L, result.finished)
        assertEquals(1, finalPolls)
        assertTrue(peer.closed)
    }
    @Test fun pollFailureAfterFirstPeerNeverBecomesObservation() {
        val peer = Peer(123)
        var polls = 0
        val window = DiscoveryWindow({ 0L }, {
            if (++polls == 1) true else throw java.io.IOException()
        }, { peer }, { true })
        assertThrows(java.io.IOException::class.java) { window.observe() }
        assertTrue(peer.closed)
    }
    @Test fun noPeerCannotEstablishPolicy() {
        var clock = 0L
        val window = DiscoveryWindow({ clock }, { timeout -> clock += timeout; false },
            { error("No peer was ready") }, { true })
        assertThrows(DiscoveryRejected::class.java) { window.observe() }
    }
    @Test fun firstPeerArrivingOnlyAtDeadlineIsDeniedWithoutPolicy() {
        var clock = 0L
        val peer = Peer(123)
        val window = DiscoveryWindow({ clock }, { timeout ->
            if (timeout > 0) { clock = 5000; false } else true
        }, { peer }, { true })
        assertThrows(DiscoveryRejected::class.java) { window.observe() }
        assertTrue(peer.closed)
    }
    @Test fun ownerClosureAfterFirstPeerCannotEstablishPolicy() {
        val peer = Peer(123)
        var active = true
        var calls = 0
        val window = DiscoveryWindow({ 0L }, {
            if (++calls == 1) true else { active = false; false }
        }, { peer }, { active })
        assertThrows(DiscoveryRejected::class.java) { window.observe() }
        assertTrue(peer.closed)
    }
    @Test fun pollReturningFirstPeerAtDeadlineCannotEstablishPolicy() {
        var clock = 0L
        val peer = Peer(123)
        var queued = true
        val window = DiscoveryWindow({ clock }, {
            clock = 5000
            queued
        }, { queued = false; peer }, { true })
        assertThrows(DiscoveryRejected::class.java) { window.observe() }
        assertTrue(peer.closed)
    }
}
