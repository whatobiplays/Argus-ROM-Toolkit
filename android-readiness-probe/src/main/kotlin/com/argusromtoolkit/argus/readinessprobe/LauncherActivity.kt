package com.argusromtoolkit.argus.readinessprobe

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/** Exported entrypoint deliberately discards every incoming intent field. */
class LauncherActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(null)
        startActivity(Intent(this, ProbeControlActivity::class.java))
        finish()
    }
}
