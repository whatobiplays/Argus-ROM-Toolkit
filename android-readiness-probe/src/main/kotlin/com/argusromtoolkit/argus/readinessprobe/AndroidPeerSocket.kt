package com.argusromtoolkit.argus.readinessprobe

import android.net.LocalServerSocket
import android.net.LocalSocket
import android.os.SystemClock
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import android.system.StructPollfd
import java.io.Closeable
import java.io.FileDescriptor
import java.io.IOException
import java.io.InputStream
import java.net.SocketTimeoutException
import java.util.concurrent.*
import java.util.concurrent.atomic.AtomicBoolean

/** Owns the listener and a fixed set of connection workers. */
class AndroidPeerSocket(private val session: ProbeSession, private val report: (String) -> Unit) : Closeable {
    private val workers = ThreadPoolExecutor(2, 2, 0, TimeUnit.MILLISECONDS, SynchronousQueue())
    private val timer = ScheduledThreadPoolExecutor(1)
    private val closed = AtomicBoolean(false)
    private val active = AtomicBoolean(false)
    private val sockets = mutableSetOf<LocalSocket>()
    private val listenerLock = Any()
    private var listener: LocalServerSocket? = null
    private var acceptThread: Thread? = null
    fun start(discovery: Boolean) = synchronized(listenerLock) {
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
                    closeListener(server)
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
            } catch (_: Exception) {
                if (!closed.get()) {
                    session.close()
                    report("Transport failed; session closed")
                }
            }
            finally { try { closeListener(server) } catch (_: Exception) {}
                if (session.phase == ProbeSession.Phase.CLOSED) close()
            }
        }, "probe-accept").also { it.start() }
    }

    private fun closeListener(server: LocalServerSocket, interrupt: Boolean = false) {
        synchronized(listenerLock) {
            if (listener !== server) return
            if (interrupt) shutdown(server.fileDescriptor)
            server.close()
            listener = null
        }
    }

    internal fun registerSocket(socket: LocalSocket): Boolean {
        val registered = synchronized(sockets) {
            !closed.get() && sockets.size < 2 && sockets.add(socket)
        }
        if (!registered) socket.close()
        return registered
    }
    private fun release(socket: LocalSocket) {
        synchronized(sockets) {
            if (sockets.remove(socket)) disconnect(socket)
        }
    }

    private fun disconnect(socket: LocalSocket) {
        shutdown(socket.fileDescriptor)
        try { socket.close() } catch (_: Exception) {}
    }

    private fun shutdown(descriptor: FileDescriptor?) {
        // Shutdown wakes native accept and receive calls that can outlive close.
        if (descriptor != null) {
            try { Os.shutdown(descriptor, OsConstants.SHUT_RDWR) } catch (_: ErrnoException) {}
        }
    }
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
                ControlInput(socket), r, { socket.soTimeout = it }, { socket.shutdownInput() },
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

    /** LocalSocket's stream loses the errno that distinguishes idle reads from I/O errors. */
    private class ControlInput(socket: LocalSocket) : InputStream() {
        private val descriptor = socket.fileDescriptor
        private val singleByte = ByteArray(1)

        init {
            // EAGAIN only means a receive timeout on a blocking socket.
            if (Os.fcntlInt(descriptor, OsConstants.F_GETFL, 0) and OsConstants.O_NONBLOCK != 0)
                throw IOException("Control socket must be blocking")
        }

        override fun read(): Int =
            if (read(singleByte, 0, 1) < 0) -1 else singleByte[0].toInt() and 0xff

        override fun read(bytes: ByteArray, offset: Int, length: Int): Int {
            if (length == 0) return 0
            return try {
                val count = Os.read(descriptor, bytes, offset, length)
                if (count == 0) -1 else count
            } catch (failure: ErrnoException) {
                if (failure.errno == OsConstants.EAGAIN)
                    throw SocketTimeoutException().apply { initCause(failure) }
                throw IOException(failure)
            }
        }
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        session.close()
        val server = synchronized(listenerLock) { listener }
        if (server != null) {
            try { closeListener(server, interrupt = true) } catch (_: Exception) {}
        }
        synchronized(sockets) {
            sockets.forEach(::disconnect)
            sockets.clear()
        }
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
