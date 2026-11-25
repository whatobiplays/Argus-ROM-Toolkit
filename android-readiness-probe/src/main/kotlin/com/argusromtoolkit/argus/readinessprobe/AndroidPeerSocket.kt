package com.argusromtoolkit.argus.readinessprobe

import android.net.LocalServerSocket
import android.net.LocalSocket
import android.os.SystemClock
import android.system.Os
import android.system.OsConstants
import android.system.StructPollfd
import java.io.Closeable
import java.util.concurrent.*
import java.util.concurrent.atomic.AtomicBoolean

/** Owns a fixed worker set. Closing sockets interrupts blocked native I/O. */
class AndroidPeerSocket(private val session: ProbeSession, private val report: (String) -> Unit) : Closeable {
    private val workers = ThreadPoolExecutor(2, 2, 0, TimeUnit.MILLISECONDS, SynchronousQueue())
    private val timer = ScheduledThreadPoolExecutor(1)
    private val closed = AtomicBoolean(false)
    private val active = AtomicBoolean(false)
    private val sockets = mutableSetOf<LocalSocket>()
    private var listener: LocalServerSocket? = null
    private var acceptThread: Thread? = null
    fun start(discovery: Boolean) {
        check(listener == null && !closed.get())
        check(session.phase == if (discovery) ProbeSession.Phase.DISCOVERY else ProbeSession.Phase.ENFORCING)
        val server = LocalServerSocket(session.endpoint)
        listener = server
        timer.schedule({ close() }, session.remaining(), TimeUnit.MILLISECONDS)
        acceptThread = Thread({
            try {
                if (discovery) {
                    val observation = DiscoveryWindow(
                        { SystemClock.elapsedRealtime() },
                        { timeout ->
                            val descriptor = StructPollfd().apply {
                                fd = server.fileDescriptor
                                events = OsConstants.POLLIN.toShort()
                            }
                            val ready = Os.poll(arrayOf(descriptor), timeout)
                            val errors = OsConstants.POLLERR or OsConstants.POLLHUP or OsConstants.POLLNVAL
                            if (descriptor.revents.toInt() and errors != 0) throw DiscoveryRejected()
                            ready > 0 && descriptor.revents.toInt() and OsConstants.POLLIN != 0
                        },
                        { NativePeerConnection(server.accept()) },
                        { !closed.get() && session.remaining() > 0 },
                    ).observe()
                    server.close()
                    listener = null
                    session.observed(observation.uid)
                    report("Discovery denied one peer. UID: ${observation.uid}. Session: ${session.identity}; attempt: ${session.attempt}; endpoint: ${session.endpoint}; Android elapsed interval: ${observation.started}..${observation.finished}. Confirm host correlation separately; clocks are independent.")
                    return@Thread
                }
                while (!closed.get()) {
                    val socket = server.accept()
                    val uid = try { socket.peerCredentials.uid } catch (_: Exception) { socket.close(); continue }
                    if (uid != session.pinnedUid) { socket.close(); continue }
                    if (!registerSocket(socket)) continue
                    val ownsRead = active.compareAndSet(false, true)
                    try { workers.execute { handle(socket, ownsRead) } }
                    catch (_: RejectedExecutionException) { if (ownsRead) active.set(false); release(socket) }
                }
            } catch (_: Exception) { session.close(); report("Transport failed; session closed") }
            finally { try { server.close() } catch (_: Exception) {}
                if (session.phase == ProbeSession.Phase.CLOSED) close()
            }
        }, "probe-accept").also { it.start() }
    }
    internal fun registerSocket(socket: LocalSocket): Boolean {
        val registered = synchronized(sockets) {
            !closed.get() && sockets.size < 2 && sockets.add(socket)
        }
        if (!registered) socket.close()
        return registered
    }
    private fun release(socket: LocalSocket) { synchronized(sockets) { sockets.remove(socket) }; try { socket.close() } catch (_: Exception) {} }
    private fun handle(socket: LocalSocket, ownsRead: Boolean) {
        val start = SystemClock.elapsedRealtime()
        val expiry = timer.schedule({ release(socket) }, minOf(5000, session.remaining()), TimeUnit.MILLISECONDS)
        var requestExpiry: ScheduledFuture<*>? = null
        var request: Request? = null
        try {
            socket.soTimeout = 5000
            val body = ReadinessProtocol.readFrame(socket.inputStream, ReadinessProtocol.REQUEST_CAP)
            request = try { ReadinessProtocol.request(body) } catch (failure: ProtocolFailure) {
                val ids = ReadinessProtocol.failureIdentity(body) ?: return
                ReadinessProtocol.writeFrame(socket.outputStream, ReadinessProtocol.response(ids, failure.code, failure.stage, 0, 0)); return
            }
            val r = request
            if (!session.admit(r)) throw ProtocolFailure("MalformedRequest", "Validate")
            if (!ownsRead) throw ProtocolFailure("Busy", "Read")
            val deadline = start + minOf(r.budget, 5000, session.remaining())
            if (SystemClock.elapsedRealtime() >= deadline) throw ProtocolFailure("TimedOut", "Read")
            requestExpiry = timer.schedule({ release(socket) }, (deadline - SystemClock.elapsedRealtime()).coerceAtLeast(0), TimeUnit.MILLISECONDS)
            val bytes = ActiveRead(
                socket.inputStream, r, { socket.soTimeout = it }, { socket.shutdownInput() },
                { minOf(deadline - SystemClock.elapsedRealtime(), session.remaining()) },
            ).run {
                ReadinessProtocol.response(r, null, "Read", start, SystemClock.elapsedRealtime())
            } ?: return
            ReadinessProtocol.writeFrame(socket.outputStream, bytes)
        } catch (_: ControlReleaseFailure) {
            close()
            report("Control reader release unverified; session closed")
        } catch (failure: ProtocolFailure) {
            request?.let { try { ReadinessProtocol.writeFrame(socket.outputStream, ReadinessProtocol.response(it, failure.code, failure.stage, 0, 0)) } catch (_: Exception) {} }
        } catch (_: Exception) { /* Transport failure exposes no raw diagnostic data. */ }
        finally { requestExpiry?.cancel(false); expiry.cancel(false); if (ownsRead) active.set(false); release(socket) }
    }
    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        session.close()
        try { listener?.close() } catch (_: Exception) {}
        synchronized(sockets) { sockets.toList().forEach { try { it.close() } catch (_: Exception) {} }; sockets.clear() }
        workers.shutdownNow(); timer.shutdownNow()
        // A separate bounded join avoids blocking the owner UI on native teardown.
        Thread({
            val releaseDeadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(1)
            acceptThread?.join(500)
            if (!workers.awaitTermination((releaseDeadline - System.nanoTime()).coerceAtLeast(0), TimeUnit.NANOSECONDS) || acceptThread?.isAlive == true)
                report("Resource release unverified; do not restart")
        }, "probe-release").start()
    }
}
