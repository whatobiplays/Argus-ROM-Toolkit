package com.argusromtoolkit.argus.readinessprobe

import android.app.Activity
import android.os.Bundle
import android.os.SystemClock
import android.view.MotionEvent
import android.view.WindowManager
import android.widget.*

/** Owner-attended controls. Nothing is restored after leaving this Activity. */
class ProbeControlActivity : Activity() {
    private val session = ProbeSession { SystemClock.elapsedRealtime() }
    private var transport: AndroidPeerSocket? = null
    private lateinit var status: TextView
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(null)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        val layout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(24, 24, 24, 24) }
        val scroll = ScrollView(this).apply { addView(layout) }; setContentView(scroll)
        fun field(label: String) = EditText(this).apply {
            hint = label; isSingleLine = true; isSaveEnabled = false
            filters = arrayOf(android.text.InputFilter.LengthFilter(100)); layout.addView(this)
        }
        status = TextView(this).apply { text = "Inactive. Use only an approved host session."; layout.addView(this) }
        val identity = field("Session identity (32 lowercase hex)")
        val endpoint = field("Approved abstract socket name")
        val attempt = field("Discovery attempt identity (32 lowercase hex)")
        val confirmSession = field("Re-enter correlated session identity")
        val confirmAttempt = field("Re-enter correlated discovery attempt")
        val confirmed = CheckBox(this).apply { text = "I verified exactly one matching host attempt through the approved owned forward"; layout.addView(this) }
        val uid = field("Manually approved UID (no default)")
        fun button(label: String, action: () -> Unit) {
            layout.addView(Button(this).apply {
                text = label; filterTouchesWhenObscured = true
                setOnClickListener {
                    try { action() } catch (_: Exception) {
                        transport?.close(); session.close(); status.text = "Session rejected. No restart is permitted in this Activity."
                    }
                }
            })
        }
        button("Configure and arm deny-only discovery") {
            session.configure(identity.text.toString(), endpoint.text.toString(), attempt.text.toString())
            session.armDiscovery()
            transport = AndroidPeerSocket(session) { message -> runOnUiThread { status.text = message } }
            transport!!.start(true)
            status.text = "Discovery armed for five seconds. Every connection is denied."
        }
        button("Confirm correlated discovery") {
            session.confirm(confirmSession.text.toString(), confirmAttempt.text.toString(), confirmed.isChecked)
            status.text = "Correlation confirmed. Enter the separately approved UID."
        }
        button("Approve UID and start enforcement") {
            val value = uid.text.toString()
            require(value.matches(Regex("0|[1-9][0-9]{0,9}")))
            session.enforce(value.toInt())
            transport!!.start(false)
            status.text = "Enforcing the explicitly approved UID."
        }
        button("Stop session") { transport?.close(); session.close(); status.text = "Closed" }
    }
    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (event.flags and (MotionEvent.FLAG_WINDOW_IS_OBSCURED or MotionEvent.FLAG_WINDOW_IS_PARTIALLY_OBSCURED) != 0) return false
        return super.dispatchTouchEvent(event)
    }
    override fun onPause() { transport?.close(); session.close(); super.onPause() }
    override fun onDestroy() { transport?.close(); session.close(); super.onDestroy() }
    override fun onSaveInstanceState(outState: Bundle) { /* Session authority is never persisted. */ }
}
