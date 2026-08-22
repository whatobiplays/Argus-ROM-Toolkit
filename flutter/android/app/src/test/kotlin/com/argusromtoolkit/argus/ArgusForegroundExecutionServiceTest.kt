package com.argusromtoolkit.argus

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class ArgusForegroundExecutionServiceTest {
    @Test
    fun progressOnlyChangesDoNotChangeNotificationIdentity() {
        val before = ForegroundExecutionProjection(
            activeJobCount = 1,
            completedUnits = 4,
            totalUnits = 10,
            phase = "indexing",
            statusKey = "scan.indexing",
            cancellableJobRunId = "job-1",
        )
        val after = before.copy(completedUnits = 5)

        assertEquals(before.notificationIdentity(), after.notificationIdentity())
    }

    @Test
    fun activeCountOrCancelTargetChangesNotificationIdentity() {
        val before = ForegroundExecutionProjection(
            activeJobCount = 1,
            cancellableJobRunId = "job-1",
        )

        assertNotEquals(
            before.notificationIdentity(),
            before.copy(activeJobCount = 2).notificationIdentity(),
        )
        assertNotEquals(
            before.notificationIdentity(),
            before.copy(cancellableJobRunId = "job-2").notificationIdentity(),
        )
    }

    @Test
    fun acquisitionWaitsForForegroundReadyAfterFinalStopHandoff() {
        var startRequests = 0
        var stopRequests = 0
        val host = ArgusForegroundExecutionHost(
            { startRequests++ },
            { stopRequests++ },
        )
        val serviceA = ArgusForegroundExecutionService()
        val acquisitionA = RecordingResult()

        host.acquireLibraryScanLease(acquisitionA)
        host.onServiceCreated(serviceA)
        host.onServiceForegroundReady(serviceA)
        assertEquals(1, acquisitionA.successCalls)
        assertEquals(1, startRequests)

        host.releaseLease("lease-1", RecordingResult())
        assertEquals(1, stopRequests)

        val acquisitionB = RecordingResult()
        host.acquireLibraryScanLease(acquisitionB)
        assertEquals(0, acquisitionB.successCalls)

        host.onServiceDestroyed(serviceA)
        assertEquals(2, startRequests)
        assertEquals(0, acquisitionB.successCalls)

        val serviceB = ArgusForegroundExecutionService()
        host.onServiceCreated(serviceB)
        host.onServiceForegroundReady(serviceB)
        assertEquals(1, acquisitionB.successCalls)
        assertEquals(mapOf("leaseId" to "lease-2"), acquisitionB.successValue)

        host.releaseLease("lease-2", RecordingResult())
        assertEquals(2, stopRequests)
        host.onServiceDestroyed(serviceB)
    }

    @Test
    fun hostLossFailsPendingHandoffWithoutReacquiring() {
        var startRequests = 0
        val host = ArgusForegroundExecutionHost(
            { startRequests++ },
            {},
        )
        val service = ArgusForegroundExecutionService()
        val events = RecordingEventSink()
        host.setEventSink(events)
        val acquisitionA = RecordingResult()
        val acquisitionB = RecordingResult()

        host.acquireLibraryScanLease(acquisitionA)
        host.onServiceCreated(service)
        host.acquireLibraryScanLease(acquisitionB)
        host.onServiceDestroyed(service)

        assertEquals(1, startRequests)
        assertEquals(ArgusForegroundExecutionHost.ERROR_FOREGROUND_SERVICE_LOST,
            acquisitionA.errorCode)
        assertEquals(ArgusForegroundExecutionHost.ERROR_FOREGROUND_SERVICE_LOST,
            acquisitionB.errorCode)
        assertEquals(
            listOf(ArgusForegroundExecutionHost.EVENT_HOST_LOST),
            events.events.map { it[ArgusForegroundExecutionHost.KEY_EVENT] },
        )
    }

    @Test
    fun timeoutInvalidatesLiveLeaseWithoutStartingReplacement() {
        var startRequests = 0
        val host = ArgusForegroundExecutionHost(
            { startRequests++ },
            {},
        )
        val service = ArgusForegroundExecutionService()
        val events = RecordingEventSink()
        host.setEventSink(events)
        val acquisition = RecordingResult()

        host.acquireLibraryScanLease(acquisition)
        host.onServiceCreated(service)
        host.onServiceForegroundReady(service)
        host.onServiceTimeout(service)
        val pendingAcquisition = RecordingResult()
        host.acquireLibraryScanLease(pendingAcquisition)
        assertEquals(0, pendingAcquisition.successCalls)
        host.onServiceDestroyed(service)

        assertEquals(1, startRequests)
        assertEquals(
            ArgusForegroundExecutionHost.ERROR_FOREGROUND_SERVICE_LOST,
            pendingAcquisition.errorCode,
        )
        assertEquals(
            listOf(ArgusForegroundExecutionHost.EVENT_TIMED_OUT),
            events.events.map { it[ArgusForegroundExecutionHost.KEY_EVENT] },
        )
    }

    @Test
    fun postStopStartRejectionFailsPendingLeaseWithoutOrphanState() {
        var startRequests = 0
        var stopRequests = 0
        val host = ArgusForegroundExecutionHost(
            {
                startRequests++
                if (startRequests == 2) throw IllegalStateException("rejected")
            },
            { stopRequests++ },
        )
        val service = ArgusForegroundExecutionService()
        val acquisitionA = RecordingResult()
        host.acquireLibraryScanLease(acquisitionA)
        host.onServiceCreated(service)
        host.onServiceForegroundReady(service)
        host.releaseLease("lease-1", RecordingResult())

        val acquisitionB = RecordingResult()
        host.acquireLibraryScanLease(acquisitionB)
        assertEquals(0, acquisitionB.successCalls)
        host.onServiceDestroyed(service)

        assertEquals(
            ArgusForegroundExecutionHost.ERROR_FOREGROUND_SERVICE_UNAVAILABLE,
            acquisitionB.errorCode,
        )
        assertEquals(2, startRequests)
        assertEquals(1, stopRequests)

        val staleRelease = RecordingResult()
        host.releaseLease("lease-2", staleRelease)
        assertEquals(1, staleRelease.successCalls)
        assertEquals(1, stopRequests)
    }

    @Test
    fun repeatedReleaseIsHarmlessAfterFinalTeardown() {
        var stopRequests = 0
        val host = ArgusForegroundExecutionHost(
            {},
            { stopRequests++ },
        )
        val service = ArgusForegroundExecutionService()
        val acquisition = RecordingResult()
        host.acquireLibraryScanLease(acquisition)
        host.onServiceCreated(service)
        host.onServiceForegroundReady(service)
        host.releaseLease("lease-1", RecordingResult())
        host.onServiceDestroyed(service)

        val repeatedRelease = RecordingResult()
        host.releaseLease("lease-1", repeatedRelease)
        assertEquals(1, repeatedRelease.successCalls)
        assertEquals(1, stopRequests)
    }

    private class RecordingResult : MethodChannel.Result {
        var successCalls = 0
        var successValue: Any? = null
        var errorCode: String? = null

        override fun success(result: Any?) {
            successCalls++
            successValue = result
        }

        override fun error(code: String, message: String?, details: Any?) {
            errorCode = code
        }

        override fun notImplemented() = Unit
    }

    private class RecordingEventSink : EventChannel.EventSink {
        val events = mutableListOf<Map<*, *>>()

        override fun success(event: Any?) {
            if (event is Map<*, *>) events += event
        }

        override fun error(code: String, message: String?, details: Any?) = Unit

        override fun endOfStream() = Unit
    }
}
