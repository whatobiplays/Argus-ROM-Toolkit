package com.argusromtoolkit.argus

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Narrow Android platform channel for Slice P02-001.
 *
 * It exposes only readiness facts and actions: the live All files access
 * snapshot, the app-private standard data directory, the optional
 * notification request, and the All files settings launcher. The OS is the
 * only authority for permission state; a persisted flag records only that the
 * optional notification prompt reached a terminal user response.
 */
class ArgusPlatformBridge(
    application: ArgusApplication,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val application = application
    private val preferences: SharedPreferences =
        application.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
    private var attachedActivity: Activity? = null
    private var pendingNotificationResult: MethodChannel.Result? = null

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    fun attachActivity(activity: Activity) {
        attachedActivity = activity
    }

    fun detachActivity(activity: Activity) {
        if (attachedActivity === activity) {
            attachedActivity = null
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "readSnapshot" -> result.success(readSnapshot())
            "openAllFilesAccessSettings" -> openAllFilesAccessSettings(result)
            "requestNotificationPermission" -> requestNotificationPermission(result)
            else -> result.notImplemented()
        }
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode != REQUEST_NOTIFICATION_PERMISSION) return
        val pending = pendingNotificationResult ?: return
        pendingNotificationResult = null
        // An interrupted or dismissed dialog is not a terminal user response
        // and must not be recorded as completed onboarding state.
        if (permissions.isEmpty() || grantResults.isEmpty()) {
            pending.success(NotificationAuthorization.PROMPT_REQUIRED.value)
            return
        }
        val granted =
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        preferences.edit().putBoolean(KEY_NOTIFICATION_PROMPT_COMPLETED, true).apply()
        pending.success(
            if (granted) {
                NotificationAuthorization.GRANTED.value
            } else {
                NotificationAuthorization.DENIED.value
            },
        )
    }

    private fun readSnapshot(): Map<String, Any> {
        val allFilesAccessGranted = Environment.isExternalStorageManager()
        if (allFilesAccessGranted) {
            application.initializeNativeKeyring()
        }
        return mapOf(
            "allFilesAccessRequired" to true,
            "allFilesAccessGranted" to allFilesAccessGranted,
            "notificationAuthorization" to notificationAuthorizationWireValue(),
            "standardApplicationDataDirectory" to
                application.standardApplicationDataDirectory.absolutePath,
        )
    }

    private fun notificationAuthorizationWireValue(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return NotificationAuthorization.NOT_REQUIRED.value
        }
        if (hasNotificationPermission()) {
            return NotificationAuthorization.GRANTED.value
        }
        return if (preferences.getBoolean(KEY_NOTIFICATION_PROMPT_COMPLETED, false)) {
            NotificationAuthorization.DENIED.value
        } else {
            NotificationAuthorization.PROMPT_REQUIRED.value
        }
    }

    private fun hasNotificationPermission(): Boolean =
        application.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private fun openAllFilesAccessSettings(result: MethodChannel.Result) {
        val activity = attachedActivity
        if (activity == null) {
            result.error("SETTINGS_UNAVAILABLE", "No attached activity", null)
            return
        }
        val primary =
            Intent(
                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                Uri.parse("package:${application.packageName}"),
            )
        if (primary.resolveActivity(activity.packageManager) != null) {
            activity.startActivity(primary)
            result.success(null)
            return
        }
        val fallback = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
        if (fallback.resolveActivity(activity.packageManager) != null) {
            activity.startActivity(fallback)
            result.success(null)
            return
        }
        result.error("SETTINGS_UNAVAILABLE", "No settings activity available", null)
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(NotificationAuthorization.NOT_REQUIRED.value)
            return
        }
        if (hasNotificationPermission()) {
            result.success(NotificationAuthorization.GRANTED.value)
            return
        }
        val activity = attachedActivity
        if (activity == null) {
            result.error("NOTIFICATION_UNAVAILABLE", "No attached activity", null)
            return
        }
        if (pendingNotificationResult != null) {
            result.error("NOTIFICATION_BUSY", "A notification request is in flight", null)
            return
        }
        pendingNotificationResult = result
        activity.requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_NOTIFICATION_PERMISSION,
        )
    }

    private enum class NotificationAuthorization(val value: String) {
        NOT_REQUIRED("notRequired"),
        PROMPT_REQUIRED("promptRequired"),
        GRANTED("granted"),
        DENIED("denied"),
    }

    private companion object {
        const val CHANNEL = "argus/platform_readiness"
        const val PREFERENCES_NAME = "argus_platform_onboarding"
        const val KEY_NOTIFICATION_PROMPT_COMPLETED =
            "notification_prompt_completed"
        const val REQUEST_NOTIFICATION_PERMISSION = 4001
    }
}
