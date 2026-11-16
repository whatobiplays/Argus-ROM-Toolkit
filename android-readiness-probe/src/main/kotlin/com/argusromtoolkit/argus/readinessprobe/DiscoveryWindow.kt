package com.argusromtoolkit.argus.readinessprobe

import java.io.IOException

internal class DiscoveryRejected : IOException("Discovery correlation unavailable")
internal data class DiscoveryObservation(val uid: Int, val started: Long, val finished: Long)

/** Only one denied peer in a completely observed window may be offered for owner correlation. */
internal class DiscoveryWindow(
    private val now: () -> Long,
    private val poll: (Int) -> Boolean,
    private val accept: () -> PeerConnection,
    private val active: () -> Boolean,
) {
    fun observe(): DiscoveryObservation {
        val start = now()
        val end = start + 5000
        var uid: Int? = null
        while (true) {
            if (!active()) throw DiscoveryRejected()
            val remaining = end - now()
            val ready = poll(if (remaining > 0) minOf(100, remaining).toInt() else 0)
            if (ready) {
                // Always deny a queued peer, including at the final queue check.
                val observed = discoverAndDeny(accept())
                if (uid != null || now() >= end) throw DiscoveryRejected()
                uid = observed
            } else if (remaining <= 0) {
                if (!active()) throw DiscoveryRejected()
                // This zero-time poll is the terminal queue snapshot. Connections
                // arriving after it are outside discovery and never become policy.
                return DiscoveryObservation(uid ?: throw DiscoveryRejected(), start, now())
            }
        }
    }
}
