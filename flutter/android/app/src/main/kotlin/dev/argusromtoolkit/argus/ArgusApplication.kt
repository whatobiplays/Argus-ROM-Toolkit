package dev.argusromtoolkit.argus

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugins.GeneratedPluginRegistrant

/**
 * Application-scoped owner of the single cached Flutter engine.
 *
 * The Activity attaches to this engine instead of creating its own, so
 * recreation, rotation, and backgrounding never destroy or replace the Dart
 * isolate or the Argus runtime it hosts. The platform bridge is registered
 * before the Dart entrypoint runs so the prewarmed isolate can query
 * readiness immediately.
 */
class ArgusApplication : Application() {
    lateinit var flutterEngine: FlutterEngine
        private set

    lateinit var platformBridge: ArgusPlatformBridge
        private set

    lateinit var localFilesystemBridge: ArgusLocalFilesystemBridge
        private set

    lateinit var foregroundExecutionHost: ArgusForegroundExecutionHost
        private set

    lateinit var foregroundExecutionBridge: ArgusForegroundExecutionBridge
        private set

    override fun onCreate() {
        super.onCreate()
        flutterEngine = FlutterEngine(this)
        GeneratedPluginRegistrant.registerWith(flutterEngine)
        platformBridge = ArgusPlatformBridge(
            application = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
        localFilesystemBridge = ArgusLocalFilesystemBridge(
            application = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
        foregroundExecutionHost = ArgusForegroundExecutionHost(this)
        foregroundExecutionBridge = ArgusForegroundExecutionBridge(
            host = foregroundExecutionHost,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
        flutterEngine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault(),
        )
        FlutterEngineCache.getInstance().put(ENGINE_ID, flutterEngine)
    }

    companion object {
        const val ENGINE_ID = "argus_primary_engine"
    }
}
