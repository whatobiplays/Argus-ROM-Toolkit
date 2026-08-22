package com.argusromtoolkit.argus

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Publishes the completed backend-owned diagnostics archive through Android's
 * system share sheet without exposing a filesystem path or content URI to
 * Flutter.
 */
class ArgusDiagnosticsShareBridge(
    private val application: ArgusApplication,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private var attachedActivity: Activity? = null

    init {
        channel.setMethodCallHandler(::onMethodCall)
    }

    fun attachActivity(activity: Activity) {
        attachedActivity = activity
    }

    fun detachActivity(activity: Activity) {
        if (attachedActivity === activity) {
            attachedActivity = null
        }
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            SHARE_COMPLETED_STARTUP_DIAGNOSTICS -> shareCompletedArtifact(result)
            else -> result.notImplemented()
        }
    }

    private fun shareCompletedArtifact(result: MethodChannel.Result) {
        val artifact = ArgusDiagnosticsPublicationContract.resolveCompletedArtifact(
            application.standardApplicationDataDirectory,
        )
        if (artifact == null) {
            result.error(ERROR_ARTIFACT_UNAVAILABLE, null, null)
            return
        }

        val activity = attachedActivity
        if (activity == null) {
            result.error(ERROR_ACTIVITY_UNAVAILABLE, null, null)
            return
        }

        val uri = try {
            FileProvider.getUriForFile(
                activity,
                "${application.packageName}.diagnostics",
                artifact,
            )
        } catch (_: IllegalArgumentException) {
            result.error(ERROR_PROVIDER_UNAVAILABLE, null, null)
            return
        }

        val sendIntent = Intent(Intent.ACTION_SEND).apply {
            type = "application/zip"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        if (sendIntent.resolveActivity(activity.packageManager) == null) {
            result.error(ERROR_SHARE_UNAVAILABLE, null, null)
            return
        }

        val chooser = Intent.createChooser(sendIntent, null).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            activity.startActivity(chooser)
            result.success(null)
        } catch (_: ActivityNotFoundException) {
            result.error(ERROR_SHARE_UNAVAILABLE, null, null)
        } catch (_: SecurityException) {
            result.error(ERROR_SHARE_UNAVAILABLE, null, null)
        } catch (_: RuntimeException) {
            result.error(ERROR_SHARE_UNAVAILABLE, null, null)
        }
    }

    companion object {
        const val CHANNEL_NAME = "argus/diagnostics_share"
        const val SHARE_COMPLETED_STARTUP_DIAGNOSTICS =
            "shareCompletedStartupDiagnostics"
        const val ERROR_ARTIFACT_UNAVAILABLE = "ARTIFACT_UNAVAILABLE"
        const val ERROR_ACTIVITY_UNAVAILABLE = "ACTIVITY_UNAVAILABLE"
        const val ERROR_PROVIDER_UNAVAILABLE = "PROVIDER_UNAVAILABLE"
        const val ERROR_SHARE_UNAVAILABLE = "SHARE_UNAVAILABLE"
    }
}
