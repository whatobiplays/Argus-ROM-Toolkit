package dev.argusromtoolkit.argus

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private val argusApplication: ArgusApplication
        get() = application as ArgusApplication

    override fun provideFlutterEngine(context: Context): FlutterEngine =
        argusApplication.flutterEngine

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onStart() {
        super.onStart()
        argusApplication.platformBridge.attachActivity(this)
    }

    override fun onStop() {
        argusApplication.platformBridge.detachActivity(this)
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
