package com.argusromtoolkit.argus

import android.app.Activity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Qualification-only Android host evidence channel for the repository's
 * lifecycle and execution-host integration harness.
 *
 * Exposes an opaque per-Activity-instance identity to the repository-owned
 * integration-test harness so rotation and lifecycle scenarios can tell
 * Activity recreation apart from an in-place configuration change. This is
 * host evidence only: the value is never persisted, never read by product
 * code, and carries no runtime, route, or readiness authority.
 */
class ArgusQualificationBridge(
    messenger: BinaryMessenger,
    private val foregroundExecutionHost: ArgusForegroundExecutionHost? = null,
    private val isDebugBuild: Boolean = false,
) : MethodChannel.MethodCallHandler {
    private var attachedActivity: Activity? = null
    private var activityInstanceId: String? = null

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    fun attachActivity(activity: Activity, instanceId: String) {
        attachedActivity = activity
        activityInstanceId = instanceId
    }

    fun detachActivity(activity: Activity) {
        if (attachedActivity === activity) {
            attachedActivity = null
            activityInstanceId = null
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "readActivityInstanceId" -> {
                val instanceId = activityInstanceId
                if (instanceId == null) {
                    result.error(
                        "ACTIVITY_DETACHED",
                        "No Activity instance is attached",
                        null,
                    )
                } else {
                    result.success(instanceId)
                }
            }
            "rejectNextExecutionHostStart" -> {
                if (!isDebugBuild || foregroundExecutionHost == null) {
                    result.notImplemented()
                } else {
                    foregroundExecutionHost.rejectNextStartForQualification()
                    result.success(null)
                }
            }
            "triggerExecutionHostTimeout" -> {
                if (!isDebugBuild || foregroundExecutionHost == null) {
                    result.notImplemented()
                } else {
                    result.success(
                        foregroundExecutionHost.triggerTimeoutForQualification(),
                    )
                }
            }
            "triggerExecutionHostLoss" -> {
                if (!isDebugBuild || foregroundExecutionHost == null) {
                    result.notImplemented()
                } else {
                    result.success(
                        foregroundExecutionHost.triggerHostLossForQualification(),
                    )
                }
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        const val CHANNEL = "argus/android_qualification"
    }
}
