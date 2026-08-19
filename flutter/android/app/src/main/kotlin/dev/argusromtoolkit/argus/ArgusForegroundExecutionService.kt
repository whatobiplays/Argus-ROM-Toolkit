package dev.argusromtoolkit.argus

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Android foreground execution host for the already-running application.
 *
 * The service has no Dart engine, Rust runtime, database, Jobs model, or
 * cancellation authority. It only promotes itself, renders a bounded
 * projection supplied by Dart, and reports native control events back to the
 * application-scoped host.
 */
class ArgusForegroundExecutionService : Service() {
    private var lastNotificationIdentity: ForegroundNotificationIdentity? = null

    private val host: ArgusForegroundExecutionHost
        get() = (application as ArgusApplication).foregroundExecutionHost

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        host.onServiceCreated(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ArgusForegroundExecutionHost.ACTION_START -> promoteToForeground()
            ArgusForegroundExecutionHost.ACTION_STOP -> stopSelf(startId)
            ArgusForegroundExecutionHost.ACTION_CANCEL -> {
                intent.getStringExtra(ArgusForegroundExecutionHost.EXTRA_JOB_RUN_ID)
                    ?.let(host::onCancelRequested)
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        host.onServiceDestroyed(this)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /** API 35+ callback for the platform's data-sync foreground budget. */
    override fun onTimeout(startId: Int, fgsType: Int) {
        host.onServiceTimeout(this)
        stopSelf(startId)
    }

    /** Refreshes only the notification projection. */
    fun updateNotification(projection: ForegroundExecutionProjection) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val identity = projection.notificationIdentity()
            if (identity == lastNotificationIdentity) return
            lastNotificationIdentity = identity
            getSystemService(NotificationManager::class.java)
                .notify(NOTIFICATION_ID, buildNotification(projection))
        }
    }

    private fun promoteToForeground() {
        val currentProjection = host.currentProjection()
        lastNotificationIdentity = currentProjection.notificationIdentity()
        val notification = buildNotification(currentProjection)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        host.onServiceForegroundReady(this)
    }

    private fun buildNotification(projection: ForegroundExecutionProjection): Notification {
        val text = if (projection.activeJobCount == 0) {
            "Preparing library scan"
        } else {
            "Scanning ${projection.activeJobCount} library job(s)"
        }
        val builder = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("Argus")
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
        projection.cancellableJobRunId?.let { jobRunId ->
            val cancelIntent = Intent(this, ArgusForegroundExecutionService::class.java).apply {
                action = ArgusForegroundExecutionHost.ACTION_CANCEL
                putExtra(ArgusForegroundExecutionHost.EXTRA_JOB_RUN_ID, jobRunId)
            }
            val pendingIntent = PendingIntent.getService(
                this,
                jobRunId.hashCode(),
                cancelIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            builder.addAction(
                Notification.Action.Builder(null, "Cancel", pendingIntent).build(),
            )
        }
        return builder.build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Library scans",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Foreground execution for active library scans"
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private companion object {
        const val CHANNEL_ID = "argus_library_scans"
        const val NOTIFICATION_ID = 4101
    }
}
