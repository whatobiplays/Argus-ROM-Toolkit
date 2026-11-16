package com.argusromtoolkit.argus.readinessprobe

import org.junit.Assert.*
import org.junit.Test

class PeerConnectionTest {
    private class Peer(val fail: Boolean = false) : PeerConnection {
        var closed = false
        override fun peerUid(): Int { if (fail) throw java.io.IOException(); return 123 }
        override fun input(): java.io.InputStream = error("Discovery accessed input")
        override fun output(): java.io.OutputStream = error("Discovery accessed output")
        override fun close() { closed = true }
    }
    @Test fun discoveryMeasuresCredentialsAndDeniesWithoutStreams() {
        val peer = Peer(); assertEquals(123, discoverAndDeny(peer)); assertTrue(peer.closed)
    }
    @Test fun credentialFailureStillDeniesWithoutStreams() {
        val peer = Peer(true)
        assertThrows(java.io.IOException::class.java) { discoverAndDeny(peer) }
        assertTrue(peer.closed)
    }
}
