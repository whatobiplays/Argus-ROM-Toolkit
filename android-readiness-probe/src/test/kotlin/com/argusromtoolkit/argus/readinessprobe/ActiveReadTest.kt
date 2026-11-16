package com.argusromtoolkit.argus.readinessprobe

import java.io.InputStream
import java.net.SocketTimeoutException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [30])
class ActiveReadTest {
    private val request = Request("a".repeat(32), "b".repeat(32), "c".repeat(32), 5000)
    /** Deterministic timeout, then a control event released only after work starts. */
    private class DelayedInput(private val bytes: ByteArray?) : InputStream() {
        val workStarted = CountDownLatch(1)
        val eventRead = CountDownLatch(1)
        var initial = true
        var offset = 0
        @Volatile var closed = false
        override fun read(): Int {
            if (initial) { initial = false; throw SocketTimeoutException() }
            check(workStarted.await(1, TimeUnit.SECONDS))
            if (closed) return -1
            eventRead.countDown()
            return if (bytes == null || offset >= bytes.size) -1 else bytes[offset++].toInt() and 255
        }
        override fun close() { closed = true; workStarted.countDown() }
    }
    private fun cancel(): ByteArray {
        val body = "{\"protocol_id\":\"argus.product-observer\",\"protocol_version\":1,\"request_id\":\"${request.requestId}\",\"connection_id\":\"${request.connectionId}\",\"attempt_id\":\"${request.attemptId}\",\"control\":\"Cancel\"}".toByteArray()
        return java.io.ByteArrayOutputStream().also { java.io.DataOutputStream(it).apply { writeInt(body.size); write(body) } }.toByteArray()
    }
    @Test fun cancellationAfterInitialTimeoutPreventsReady() {
        val input = DelayedInput(cancel())
        val read = ActiveRead(input, request, {}, { input.close() }, { 5000 })
        val failure = assertThrows(ProtocolFailure::class.java) {
            read.run {
                input.workStarted.countDown()
                input.eventRead.await(200, TimeUnit.MILLISECONDS)
                byteArrayOf(1)
            }
        }
        assertEquals("Cancelled", failure.code)
    }
    @Test fun eofAfterInitialTimeoutPreventsReady() {
        val input = DelayedInput(null)
        val result = ActiveRead(input, request, {}, { input.close() }, { 5000 }).run {
            input.workStarted.countDown()
            input.eventRead.await(200, TimeUnit.MILLISECONDS)
            byteArrayOf(1)
        }
        assertNull(result)
    }

    private class IdleInput : InputStream() {
        val shutdown = CountDownLatch(1)
        val readers = java.util.concurrent.atomic.AtomicInteger()
        override fun read(): Int {
            readers.incrementAndGet()
            try {
                return if (shutdown.await(10, TimeUnit.MILLISECONDS)) -1 else throw SocketTimeoutException()
            } finally { readers.decrementAndGet() }
        }
        override fun close() { shutdown.countDown() }
    }
    @Test fun normalCompletionStopsAndJoinsControlReader() {
        val input = IdleInput()
        val bytes = ActiveRead(input, request, {}, { input.close() }, { 5000 }).run { byteArrayOf(1, 2) }
        assertArrayEquals(byteArrayOf(1, 2), bytes)
        assertEquals(0L, input.shutdown.count)
        assertEquals(0, input.readers.get())
    }
    @Test fun assemblyFailureStillStopsAndJoinsControlReader() {
        val input = IdleInput()
        val failure = assertThrows(IllegalStateException::class.java) {
            ActiveRead(input, request, {}, { input.close() }, { 5000 }).run { error("assembly failed") }
        }
        assertEquals("assembly failed", failure.message)
        assertEquals(0L, input.shutdown.count)
        assertEquals(0, input.readers.get())
    }
    @Test fun expiredReadCannotCommitSuccess() {
        val input = IdleInput()
        val remaining = java.util.concurrent.atomic.AtomicLong(5000)
        val failure = assertThrows(ProtocolFailure::class.java) {
            ActiveRead(input, request, {}, { input.close() }, { remaining.get() }).run {
                remaining.set(0); byteArrayOf(1)
            }
        }
        assertEquals("TimedOut", failure.code)
        assertEquals(0, input.readers.get())
    }
    @Test fun mismatchedCancellationAfterInitialTimeoutCannotCommitSuccess() {
        val wrong = String(cancel().drop(4).toByteArray()).replace("c".repeat(32), "d".repeat(32)).toByteArray()
        val framed = java.io.ByteArrayOutputStream().also { java.io.DataOutputStream(it).apply { writeInt(wrong.size); write(wrong) } }.toByteArray()
        val input = DelayedInput(framed)
        val failure = assertThrows(ProtocolFailure::class.java) {
            ActiveRead(input, request, {}, { input.close() }, { 5000 }).run {
                input.workStarted.countDown(); input.eventRead.await(200, TimeUnit.MILLISECONDS); byteArrayOf(1)
            }
        }
        assertEquals("MalformedRequest", failure.code)
    }

    @Test fun readerThatCannotBeReleasedCannotReturnReady() {
        val unblock = CountDownLatch(1)
        val entered = CountDownLatch(1)
        val stopped = CountDownLatch(1)
        val input = object : InputStream() {
            override fun read(): Int {
                entered.countDown()
                try { unblock.await(); return -1 } finally { stopped.countDown() }
            }
        }
        try {
            assertThrows(ControlReleaseFailure::class.java) {
                ActiveRead(input, request, {}, {}, { 5000 }).run {
                    check(entered.await(1, TimeUnit.SECONDS)); error("assembly failed")
                }
            }
        } finally {
            unblock.countDown()
            assertTrue(stopped.await(1, TimeUnit.SECONDS))
        }
    }

    @Test fun partialControlCannotDripFeedPastAbsoluteRequestBudget() {
        for (budget in listOf(5L, 12L)) {
        val startWork = CountDownLatch(1)
        val firstControl = CountDownLatch(1)
        val remaining = java.util.concurrent.atomic.AtomicLong(budget)
        val beyondBudget = java.util.concurrent.atomic.AtomicBoolean(false)
        var position = 0
        val control = cancel()
        val input = object : InputStream() {
            override fun read(): Int {
                check(startWork.await(1, TimeUnit.SECONDS))
                firstControl.countDown()
                if (remaining.get() <= 0) { beyondBudget.set(true); throw SocketTimeoutException() }
                remaining.decrementAndGet()
                return control[position++].toInt() and 255
            }
            override fun read(bytes: ByteArray, offset: Int, length: Int): Int {
                bytes[offset] = read().toByte(); return 1
            }
        }
        val failure = assertThrows(ProtocolFailure::class.java) {
            ActiveRead(input, request, {}, {}, { remaining.get() }).run {
                startWork.countDown(); firstControl.await(1, TimeUnit.SECONDS); byteArrayOf(1)
            }
        }
        assertEquals("TimedOut", failure.code)
        assertFalse("No read may start after the absolute budget is exhausted", beyondBudget.get())
        }
    }
    @Test fun secondControlBeforeTerminalIsRejectedEvenWhenAvailableReportsZero() {
        for (controls in listOf(cancel() + cancel(), cancel() + byteArrayOf(0))) {
        val input = DelayedInput(controls)
        val failure = assertThrows(ProtocolFailure::class.java) {
            ActiveRead(input, request, {}, { input.close() }, { 5000 }).run {
                input.workStarted.countDown(); input.eventRead.await(200, TimeUnit.MILLISECONDS); byteArrayOf(1)
            }
        }
        assertEquals("MalformedRequest", failure.code)
        }
    }
}
