package com.argusromtoolkit.argus.readinessprobe

import android.net.LocalSocket
import java.io.Closeable
import java.io.InputStream
import java.io.OutputStream

/** Credential access is separate from application streams so discovery cannot consume data. */
interface PeerConnection : Closeable {
    fun peerUid(): Int
    fun input(): InputStream
    fun output(): OutputStream
}
class NativePeerConnection(private val socket: LocalSocket) : PeerConnection {
    override fun peerUid(): Int = socket.peerCredentials.uid
    override fun input(): InputStream = socket.inputStream
    override fun output(): OutputStream = socket.outputStream
    override fun close() = socket.close()
}
/** Every discovery connection is denied, including when credential lookup fails. */
fun discoverAndDeny(connection: PeerConnection): Int = connection.use { it.peerUid() }
