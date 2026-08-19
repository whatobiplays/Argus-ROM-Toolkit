package dev.argusromtoolkit.argus

import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Application-owned, process-local foreground execution lease host.
 *
 * A lease only proves that Android accepted foreground execution hosting. The
 * durable JobRun, scan state, cancellation intent, and recovery authority stay
 * in the already-running Flutter/Rust application. This class therefore keeps
 * only transient lease IDs, a bounded notification projection, and callbacks
 * to the Dart host.
 */
class ArgusForegroundExecutionHost private constructor(
    private val application: ArgusApplication?,
    private val startForegroundServiceOverride: (() -> Unit)?,
    private val stopServiceOverride: (() -> Unit)?,
    private val scheduleDelayed: (Runnable, Long) -> Unit,
) {
    constructor(application: ArgusApplication) : this(
        application,
        null,
        null,
        { runnable, delay -> Handler(Looper.getMainLooper()).postDelayed(runnable, delay) },
    )

    internal constructor(
        startForegroundService: () -> Unit,
        stopService: () -> Unit,
    ) : this(null, startForegroundService, stopService, { _, _ -> })

    private val leases = LinkedHashSet<String>()
    private val pendingAcquisitions = LinkedHashMap<String, MethodChannel.Result>()
    private var nextLeaseId = 1L
    private var serviceState = ServiceState.ABSENT
    private var expectedServiceStop = false
    private var hostSignalStop = false
    private var eventSink: EventChannel.EventSink? = null
    private var service: ArgusForegroundExecutionService? = null
    private var projection = ForegroundExecutionProjection()

    /** Native service lifecycle owned by this application-scoped host. */
    private enum class ServiceState {
        ABSENT,
        STARTING,
        LIVE,
        STOPPING,
    }

    /** Registers the Dart event sink for native host callbacks. */
    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    /** Starts or joins the one application-scoped foreground service. */
    fun acquireLibraryScanLease(result: MethodChannel.Result) {
        val leaseId = "lease-${nextLeaseId++}"
        leases += leaseId
        when (serviceState) {
            ServiceState.LIVE -> {
                result.success(mapOf(KEY_LEASE_ID to leaseId))
            }
            ServiceState.STARTING, ServiceState.STOPPING -> {
                pendingAcquisitions[leaseId] = result
            }
            ServiceState.ABSENT -> {
                pendingAcquisitions[leaseId] = result
                startServiceIfNeeded()
            }
        }
    }

    /** Releases one opaque lease; repeated or stale releases are harmless. */
    fun releaseLease(leaseId: String, result: MethodChannel.Result) {
        if (leaseId.isEmpty() || leaseId.length > MAX_LEASE_ID_LENGTH) {
            result.error(ERROR_MALFORMED_REQUEST, null, null)
            return
        }
        pendingAcquisitions.remove(leaseId)?.success(null)
        leases.remove(leaseId)
        if (leases.isEmpty()) stopServiceIfNeeded()
        result.success(null)
    }

    /** Stores and publishes the bounded secondary notification projection. */
    fun updateProjection(value: ForegroundExecutionProjection) {
        projection = value
        service?.updateNotification(value)
    }

    /** Gives the service a callback target without transferring any authority. */
    fun onServiceCreated(service: ArgusForegroundExecutionService) {
        this.service = service
        if (serviceState == ServiceState.ABSENT) {
            serviceState = ServiceState.STARTING
        }
    }

    /** Completes pending acquisitions only after foreground promotion succeeds. */
    fun onServiceForegroundReady(service: ArgusForegroundExecutionService) {
        if (this.service !== service || serviceState != ServiceState.STARTING) return
        serviceState = ServiceState.LIVE
        if (leases.isEmpty()) {
            stopServiceIfNeeded()
            return
        }
        val pending = pendingAcquisitions.toMap()
        pendingAcquisitions.clear()
        pending.forEach { (leaseId, result) ->
            if (leases.contains(leaseId)) {
                result.success(mapOf(KEY_LEASE_ID to leaseId))
            }
        }
    }

    /** Handles an API 35+ platform timeout without restarting the service. */
    fun onServiceTimeout(service: ArgusForegroundExecutionService) {
        if (this.service !== service || serviceState != ServiceState.LIVE) return
        hostSignalStop = true
        serviceState = ServiceState.STOPPING
        leases.clear()
        emit(mapOf(KEY_EVENT to EVENT_TIMED_OUT))
    }

    /** Handles service destruction and distinguishes expected final release. */
    fun onServiceDestroyed(service: ArgusForegroundExecutionService) {
        if (this.service !== service) return
        this.service = null
        val expected = expectedServiceStop || hostSignalStop
        val stoppedByHostSignal = hostSignalStop
        serviceState = ServiceState.ABSENT
        expectedServiceStop = false
        hostSignalStop = false
        if (!expected && leases.isNotEmpty()) {
            leases.clear()
            failPendingAcquisitions(ERROR_FOREGROUND_SERVICE_LOST)
            emit(mapOf(KEY_EVENT to EVENT_HOST_LOST))
            return
        }
        if (stoppedByHostSignal) {
            leases.clear()
            failPendingAcquisitions(ERROR_FOREGROUND_SERVICE_LOST)
            return
        }
        if (expected && leases.isNotEmpty() && pendingAcquisitions.isNotEmpty()) {
            startServiceIfNeeded()
        }
    }

    /** Emits a notification cancel request; Dart owns the Jobs mutation. */
    fun onCancelRequested(jobRunId: String) {
        if (jobRunId.isEmpty() || jobRunId.length > MAX_JOB_RUN_ID_LENGTH) return
        emit(
            mapOf(
                KEY_EVENT to EVENT_CANCEL_REQUESTED,
                KEY_JOB_RUN_ID to jobRunId,
            ),
        )
    }

    /** Returns the current projection for the service's initial notification. */
    fun currentProjection(): ForegroundExecutionProjection = projection

    private fun failPendingAcquisitions(code: String) {
        val pending = pendingAcquisitions.toMap()
        pendingAcquisitions.clear()
        pending.forEach { (leaseId, result) ->
            leases.remove(leaseId)
            result.error(code, null, null)
        }
    }

    private fun startServiceIfNeeded() {
        if (serviceState != ServiceState.ABSENT || pendingAcquisitions.isEmpty()) return
        expectedServiceStop = false
        hostSignalStop = false
        serviceState = ServiceState.STARTING
        try {
            requestForegroundServiceStart()
        } catch (_: RuntimeException) {
            serviceState = ServiceState.ABSENT
            failPendingAcquisitions(ERROR_FOREGROUND_SERVICE_UNAVAILABLE)
            return
        }
        scheduleDelayed(Runnable {
            if (serviceState == ServiceState.STARTING &&
                pendingAcquisitions.isNotEmpty()
            ) {
                failPendingAcquisitions(ERROR_FOREGROUND_SERVICE_START_TIMEOUT)
                stopServiceIfNeeded()
            }
        }, START_ACK_TIMEOUT_MS)
    }

    private fun stopServiceIfNeeded() {
        if (leases.isNotEmpty()) return
        if (serviceState == ServiceState.ABSENT ||
            serviceState == ServiceState.STOPPING
        ) return
        expectedServiceStop = true
        serviceState = ServiceState.STOPPING
        requestServiceStop()
    }

    private fun emit(event: Map<String, Any>) {
        eventSink?.success(event)
    }

    private fun requestForegroundServiceStart() {
        val override = startForegroundServiceOverride
        if (override != null) {
            override()
            return
        }
        val app = checkNotNull(application)
        app.startForegroundService(serviceIntent(app, ACTION_START))
    }

    private fun requestServiceStop() {
        val override = stopServiceOverride
        if (override != null) {
            override()
            return
        }
        val app = checkNotNull(application)
        app.stopService(serviceIntent(app, ACTION_STOP))
    }

    private fun serviceIntent(application: ArgusApplication, action: String): Intent =
        Intent(application, ArgusForegroundExecutionService::class.java).apply {
            this.action = action
        }

    companion object {
        const val CHANNEL = "argus/foreground_execution"
        const val EVENT_CHANNEL = "argus/foreground_execution/events"
        const val ACTION_START = "dev.argusromtoolkit.argus.action.START_FOREGROUND"
        const val ACTION_STOP = "dev.argusromtoolkit.argus.action.STOP_FOREGROUND"
        const val ACTION_CANCEL = "dev.argusromtoolkit.argus.action.CANCEL_JOB"
        const val EXTRA_JOB_RUN_ID = "jobRunId"
        const val KEY_LEASE_ID = "leaseId"
        const val KEY_EVENT = "event"
        const val KEY_JOB_RUN_ID = "jobRunId"
        const val EVENT_CANCEL_REQUESTED = "cancelRequested"
        const val EVENT_TIMED_OUT = "timedOut"
        const val EVENT_HOST_LOST = "hostLost"
        const val ERROR_MALFORMED_REQUEST = "MALFORMED_REQUEST"
        const val ERROR_FOREGROUND_SERVICE_UNAVAILABLE =
            "FOREGROUND_SERVICE_UNAVAILABLE"
        const val ERROR_FOREGROUND_SERVICE_START_TIMEOUT =
            "FOREGROUND_SERVICE_START_TIMEOUT"
        const val ERROR_FOREGROUND_SERVICE_LOST = "FOREGROUND_SERVICE_LOST"
        const val START_ACK_TIMEOUT_MS = 5_000L
        const val MAX_LEASE_ID_LENGTH = 128
        const val MAX_JOB_RUN_ID_LENGTH = 64
    }
}

/** Bounded data sent to the Android notification projection. */
data class ForegroundExecutionProjection(
    val activeJobCount: Int = 0,
    val completedUnits: Long? = null,
    val totalUnits: Long? = null,
    val phase: String? = null,
    val statusKey: String? = null,
    val cancellableJobRunId: String? = null,
)

/**
 * The subset of a projection that changes the visible notification action or
 * summary. Progress details remain available to the host, but do not trigger
 * a SystemUI update while the rendered notification is unchanged.
 */
internal data class ForegroundNotificationIdentity(
    val activeJobCount: Int,
    val cancellableJobRunId: String?,
)

internal fun ForegroundExecutionProjection.notificationIdentity(): ForegroundNotificationIdentity =
    ForegroundNotificationIdentity(activeJobCount, cancellableJobRunId)
