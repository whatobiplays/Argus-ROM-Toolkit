package com.argusromtoolkit.argus.readinessprobe

/** In-memory authority. A failed or recreated session cannot be resumed. */
class ProbeSession(private val now: () -> Long) {
    enum class Phase { NEW, CONFIGURED, DISCOVERY, OBSERVED, CONFIRMED, ENFORCING, CLOSED }
    var phase = Phase.NEW; private set
    var identity = ""; private set
    var endpoint = ""; private set
    var attempt = ""; private set
    var uid: Int? = null; private set
    var pinnedUid: Int? = null; private set
    private var deadline = 0L
    private val usedIds = mutableSetOf<String>()
    @Synchronized fun configure(session: String, socket: String, discovery: String) {
        check(phase == Phase.NEW)
        require(session.matches(Regex("[0-9a-f]{32}")) && discovery.matches(Regex("[0-9a-f]{32}")) && session != discovery)
        require(socket.matches(Regex("[a-zA-Z0-9_.-]{1,100}")))
        identity = session; endpoint = socket; attempt = discovery
        deadline = now() + 600_000; phase = Phase.CONFIGURED
    }
    @Synchronized fun armDiscovery() { requirePhase(Phase.CONFIGURED); phase = Phase.DISCOVERY }
    @Synchronized fun observed(peerUid: Int) {
        requirePhase(Phase.DISCOVERY)
        require(peerUid >= 0)
        uid = peerUid; phase = Phase.OBSERVED
    }
    @Synchronized fun confirm(session: String, discovery: String, exactlyOne: Boolean) {
        requirePhase(Phase.OBSERVED)
        if (session != identity || discovery != attempt || !exactlyOne) { close(); error("Correlation rejected") }
        phase = Phase.CONFIRMED
    }
    @Synchronized fun enforce(manualUid: Int) {
        requirePhase(Phase.CONFIRMED)
        if (manualUid != uid) { close(); error("Peer policy rejected") }
        pinnedUid = manualUid; phase = Phase.ENFORCING
    }
    @Synchronized fun admit(request: Request): Boolean {
        requirePhase(Phase.ENFORCING)
        val ids = listOf(request.requestId, request.connectionId, request.attemptId)
        if (ids.any { it in usedIds } || usedIds.size + 3 > 256) return false
        usedIds.addAll(ids); return true
    }
    @Synchronized fun remaining(): Long = (deadline - now()).coerceAtLeast(0)
    @Synchronized fun close() { phase = Phase.CLOSED; pinnedUid = null; uid = null; usedIds.clear() }
    private fun requirePhase(expected: Phase) {
        if (now() >= deadline) close()
        check(phase == expected) { "Session transition rejected" }
    }
}
