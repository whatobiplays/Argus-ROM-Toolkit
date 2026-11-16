package com.argusromtoolkit.argus.readinessprobe

import java.io.IOException
import java.io.InputStream
import java.net.SocketTimeoutException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Cleanup failure is terminal for the owning session. */
internal class ControlReleaseFailure : IOException("Control reader release unverified")

/**
 * Watches control input throughout response assembly. The lock serializes a control
 * observation with success commitment. Once committed, later input cannot change
 * that completed response. No application work or response write runs on the reader.
 */
internal class ActiveRead(
    private val input: InputStream,
    private val request: Request,
    private val setTimeout: (Int) -> Unit,
    private val shutdownInput: () -> Unit,
    private val remaining: () -> Long,
) {
    private sealed interface Outcome {
        data object Complete : Outcome
        data object Disconnected : Outcome
        data class Failed(val failure: ProtocolFailure) : Outcome
    }
    private val lock = Any()
    private val finishing = AtomicBoolean(false)
    private var outcome: Outcome? = null

    fun run(work: () -> ByteArray): ByteArray? {
        val started = CountDownLatch(1)
        val reader = Thread({
            while (!finishing.get()) {
                synchronized(lock) {
                    if (!finishing.get() && outcome == null) {
                        started.countDown()
                        try {
                            if (remaining() <= 0) throw ProtocolFailure("TimedOut", "Read")
                            setTimeout(minOf(10, remaining()).coerceAtLeast(1).toInt())
                            val first = try { input.read() } catch (_: SocketTimeoutException) { -2 }
                            when {
                                first == -1 -> outcome = Outcome.Disconnected
                                first >= 0 -> {
                                    val controlDeadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(1)
                                    fun controlRemaining(): Long {
                                        val nanos = controlDeadline - System.nanoTime()
                                        val frameMs = if (nanos <= 0) 0 else (nanos + 999_999) / 1_000_000
                                        return minOf(remaining(), frameMs)
                                    }
                                    val prefixed = java.io.SequenceInputStream(java.io.ByteArrayInputStream(byteArrayOf(first.toByte())), input)
                                    val bounded = DeadlineInput(prefixed, ::controlRemaining, setTimeout)
                                    val bytes = ReadinessProtocol.readFrame(bounded, ReadinessProtocol.CANCEL_CAP)
                                    ReadinessProtocol.cancel(bytes, request)
                                    // Observe a second control (even a partial prefix) before
                                    // terminalization. This bounded read replaces available(),
                                    // which says nothing about readable but unbuffered input.
                                    val trailing = try {
                                        bounded.readWithLimit(input, 10)
                                    } catch (_: SocketTimeoutException) { -2 }
                                    if (trailing >= 0) throw ProtocolFailure("MalformedRequest", "Cancel")
                                    if (controlRemaining() <= 0) throw ProtocolFailure("TimedOut", "Cancel")
                                    outcome = Outcome.Failed(ProtocolFailure("Cancelled", "Cancel"))
                                }
                            }
                        } catch (failure: ProtocolFailure) {
                            outcome = Outcome.Failed(failure)
                        } catch (_: SocketTimeoutException) {
                            // A partial control frame cannot become a successful observation.
                            outcome = Outcome.Failed(ProtocolFailure("TimedOut", "Cancel"))
                        } catch (_: IOException) {
                            outcome = Outcome.Disconnected
                        } catch (_: Exception) {
                            outcome = Outcome.Failed(ProtocolFailure("InternalError", "Cancel"))
                        }
                        if (outcome != null) finishing.set(true)
                    }
                }
            }
        }, "probe-control")
        reader.start()
        try {
            if (!started.await(1, TimeUnit.SECONDS)) throw IOException("Control reader start unverified")
            val bytes = work()
            // Prevent another blocking read; wait for an already-started observation
            // to finish before committing success under the same lock.
            finishing.set(true)
            val committed = synchronized(lock) {
                if (outcome == null) outcome = if (remaining() > 0) Outcome.Complete
                    else Outcome.Failed(ProtocolFailure("TimedOut", "Read"))
                outcome
            }
            return when (committed) {
                Outcome.Complete -> bytes
                Outcome.Disconnected -> null
                is Outcome.Failed -> throw committed.failure
                null -> error("Missing completion")
            }
        } finally {
            finishing.set(true)
            // Shutdown is also required if response assembly throws while read blocks.
            try { shutdownInput() } catch (_: Exception) { }
            try { reader.join(1000) } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                if (reader.isAlive) throw ControlReleaseFailure()
            }
            if (reader.isAlive) throw ControlReleaseFailure()
        }
    }

    /** Every blocking read shares absolute authority; progress never renews it. */
    private class DeadlineInput(
        private val input: InputStream,
        private val remaining: () -> Long,
        private val setTimeout: (Int) -> Unit,
    ) : InputStream() {
        private fun prepare(limit: Int = 1000) {
            val budget = remaining()
            if (budget <= 0) throw ProtocolFailure("TimedOut", "Cancel")
            setTimeout(minOf(limit.toLong(), budget).toInt())
        }
        private fun checkDeadline() {
            if (remaining() <= 0) throw ProtocolFailure("TimedOut", "Cancel")
        }
        fun readWithLimit(source: InputStream, limit: Int): Int {
            prepare(limit)
            return source.read().also { checkDeadline() }
        }
        override fun read(): Int = readWithLimit(input, 1000)
        override fun read(bytes: ByteArray, offset: Int, length: Int): Int {
            prepare()
            return input.read(bytes, offset, length).also { checkDeadline() }
        }
    }
}
