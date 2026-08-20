package dev.argusromtoolkit.argus

import android.content.Context
import java.util.UUID
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private val argusApplication: ArgusApplication
        get() = application as ArgusApplication

    // One opaque identity per Activity instance. It exists only for the
    // qualification harness; it is not persisted and carries no product state.
    private val qualificationInstanceId: String = UUID.randomUUID().toString()

    override fun provideFlutterEngine(context: Context): FlutterEngine =
        argusApplication.flutterEngine

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onStart() {
        super.onStart()
        argusApplication.platformBridge.attachActivity(this)
        argusApplication.diagnosticsShareBridge.attachActivity(this)
        argusApplication.qualificationBridge.attachActivity(
            this,
            qualificationInstanceId,
        )
    }

    override fun onStop() {
        argusApplication.diagnosticsShareBridge.detachActivity(this)
        argusApplication.platformBridge.detachActivity(this)
        argusApplication.qualificationBridge.detachActivity(this)
        super.onStop()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        argusApplication.platformBridge.onRequestPermissionsResult(
            requestCode,
            permissions,
            grantResults,
        )
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}
