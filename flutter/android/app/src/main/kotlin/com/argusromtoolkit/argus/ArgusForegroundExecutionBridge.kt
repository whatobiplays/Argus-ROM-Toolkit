package com.argusromtoolkit.argus

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Thin MethodChannel/EventChannel adapter for the application-owned host.
 *
 * It validates channel input and delegates all lease/event behavior to the
 * host; it never constructs Flutter engines or touches durable application
 * state.
 */
class ArgusForegroundExecutionBridge(
    private val host: ArgusForegroundExecutionHost,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    init {
        MethodChannel(messenger, ArgusForegroundExecutionHost.CHANNEL)
            .setMethodCallHandler(this)
        EventChannel(messenger, ArgusForegroundExecutionHost.EVENT_CHANNEL)
            .setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "acquireLibraryScanLease" -> host.acquireLibraryScanLease(result)
            "releaseLease" -> releaseLease(call, result)
            "updateProjection" -> updateProjection(call, result)
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        host.setEventSink(events)
    }

    override fun onCancel(arguments: Any?) {
        host.setEventSink(null)
    }

    private fun releaseLease(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        val leaseId = arguments?.get("leaseId") as? String
        if (leaseId == null) {
            result.error(ArgusForegroundExecutionHost.ERROR_MALFORMED_REQUEST, null, null)
            return
        }
        host.releaseLease(leaseId, result)
    }

    private fun updateProjection(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        if (arguments == null) {
            result.error(ArgusForegroundExecutionHost.ERROR_MALFORMED_REQUEST, null, null)
            return
        }
        val activeJobCount = (arguments["activeJobCount"] as? Number)?.toInt()
        val completedUnits = (arguments["completedUnits"] as? Number)?.toLong()
        val totalUnits = (arguments["totalUnits"] as? Number)?.toLong()
        val phase = arguments["phase"] as? String
        val statusKey = arguments["statusKey"] as? String
        val operationLabel = arguments["operationLabel"] as? String
        val cancellableJobRunId = arguments["cancellableJobRunId"] as? String
        val invalidUnits = completedUnits?.let { completed ->
            completed < 0 || totalUnits != null && completed > totalUnits
        } == true || totalUnits?.let { it < 0 } == true
        if (activeJobCount == null || activeJobCount < 0 ||
            activeJobCount > MAX_ACTIVE_JOB_COUNT ||
            invalidUnits ||
            phase?.length ?: 0 > MAX_TEXT_LENGTH ||
            statusKey?.length ?: 0 > MAX_TEXT_LENGTH ||
            operationLabel?.length ?: 0 > MAX_TEXT_LENGTH ||
            cancellableJobRunId?.length ?: 0 > ArgusForegroundExecutionHost.MAX_JOB_RUN_ID_LENGTH
        ) {
            result.error(ArgusForegroundExecutionHost.ERROR_MALFORMED_REQUEST, null, null)
            return
        }
        host.updateProjection(
            ForegroundExecutionProjection(
                activeJobCount = activeJobCount,
                completedUnits = completedUnits,
                totalUnits = totalUnits,
                phase = phase,
                statusKey = statusKey,
                operationLabel = operationLabel,
                cancellableJobRunId = cancellableJobRunId,
            ),
        )
        result.success(null)
    }

    private companion object {
        const val MAX_TEXT_LENGTH = 128
        const val MAX_ACTIVE_JOB_COUNT = 16
    }
}
