package dev.argusromtoolkit.argus

import android.app.Application
import android.os.Environment
import android.os.storage.StorageManager
import android.os.storage.StorageVolume
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

/**
 * Android mounted-volume discovery for the LocalFilesystem provider.
 *
 * This bridge reports only bounded current facts. The provider volume ID is
 * derived from the primary sentinel or a normalized removable UUID; neither
 * the mount path nor the human-readable description is an identity fallback.
 * The channel has no Activity dependency and can therefore be registered on
 * the application-scoped engine before the Dart entrypoint starts.
 */
class ArgusLocalFilesystemBridge(
    private val application: Application,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "readMountedVolumes" -> {
                try {
                    result.success(readMountedVolumes())
                } catch (error: DiscoveryException) {
                    result.error(error.code, null, null)
                } catch (_: RuntimeException) {
                    result.error(ERROR_DISCOVERY_UNAVAILABLE, null, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun readMountedVolumes(): List<Map<String, Any>> {
        val storageManager =
            application.getSystemService(StorageManager::class.java)
                ?: throw DiscoveryException(ERROR_DISCOVERY_UNAVAILABLE)
        val volumes = storageManager.storageVolumes.mapNotNull(::mountedVolumeFact)
        if (volumes.size > MAX_VOLUMES || volumes.count { it[KEY_IS_PRIMARY] == true } != 1) {
            throw DiscoveryException(ERROR_MALFORMED_SNAPSHOT)
        }
        val identities = volumes.map { it[KEY_PROVIDER_VOLUME_ID] as String }
        if (identities.toSet().size != identities.size) {
            throw DiscoveryException(ERROR_MALFORMED_SNAPSHOT)
        }
        return volumes
    }

    private fun mountedVolumeFact(volume: StorageVolume): Map<String, Any>? {
        val directory = volume.directory ?: return null
        val state = Environment.getExternalStorageState(directory)
        if (state != Environment.MEDIA_MOUNTED &&
            state != Environment.MEDIA_MOUNTED_READ_ONLY
        ) {
            return null
        }
        val description = volume.getDescription(application)?.trim()
        if (description.isNullOrEmpty()) return null
        val providerVolumeId = if (volume.isPrimary) {
            PRIMARY_VOLUME_ID
        } else {
            val uuid = volume.uuid?.trim()?.uppercase(Locale.ROOT)
            if (uuid.isNullOrEmpty()) return null
            uuid
        }
        return mapOf(
            KEY_PROVIDER_VOLUME_ID to providerVolumeId,
            KEY_TRANSIENT_MOUNT_PATH to directory.absolutePath,
            KEY_SAFE_DISPLAY_NAME to description,
            KEY_IS_PRIMARY to volume.isPrimary,
            KEY_IS_REMOVABLE to volume.isRemovable,
        )
    }

    private class DiscoveryException(val code: String) : RuntimeException()

    private companion object {
        const val CHANNEL = "argus/local_filesystem_platform"
        const val PRIMARY_VOLUME_ID = "primary"
        const val MAX_VOLUMES = 32
        const val ERROR_DISCOVERY_UNAVAILABLE = "DISCOVERY_UNAVAILABLE"
        const val ERROR_MALFORMED_SNAPSHOT = "MALFORMED_SNAPSHOT"
        const val KEY_PROVIDER_VOLUME_ID = "providerVolumeId"
        const val KEY_TRANSIENT_MOUNT_PATH = "transientMountPath"
        const val KEY_SAFE_DISPLAY_NAME = "safeDisplayName"
        const val KEY_IS_PRIMARY = "isPrimary"
        const val KEY_IS_REMOVABLE = "isRemovable"
    }
}
