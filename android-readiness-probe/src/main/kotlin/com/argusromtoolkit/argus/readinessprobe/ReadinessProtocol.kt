package com.argusromtoolkit.argus.readinessprobe

import android.util.JsonReader
import android.util.JsonToken
import android.util.JsonWriter
import java.io.*
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction

/** Closed, bounded ObserverV1 codec. Errors contain no input or peer data. */
class ProtocolFailure(val code: String = "MalformedRequest", val stage: String = "Parse") : IOException(code)
data class Request(val requestId: String, val connectionId: String, val attemptId: String, val budget: Long)
object ReadinessProtocol {
    const val REQUEST_CAP = 274
    const val CANCEL_CAP = 227
    const val RESPONSE_CAP = 393
    private const val PROTOCOL = "argus.product-observer"
    private data class NumberToken(val text: String)
    private fun parse(bytes: ByteArray): Map<String, Any> {
        try {
            val text = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
            if (text.startsWith('\uFEFF')) throw ProtocolFailure()
            var members = 0
            val reader = JsonReader(StringReader(text))
            fun obj(depth: Int): Map<String, Any> {
                if (depth > 3) throw ProtocolFailure()
                val fields = linkedMapOf<String, Any>()
                reader.beginObject()
                while (reader.hasNext()) {
                    val name = reader.nextName()
                    if (fields.containsKey(name) || fields.size >= 8 || ++members > 11) throw ProtocolFailure()
                    fields[name] = when (reader.peek()) {
                        JsonToken.BEGIN_OBJECT -> obj(depth + 1)
                        JsonToken.STRING -> reader.nextString().also { value ->
                            var i = 0
                            while (i < value.length) {
                                val ch = value[i++]
                                if (ch.isHighSurrogate()) {
                                    if (i == value.length || !value[i++].isLowSurrogate()) throw ProtocolFailure()
                                } else if (ch.isLowSurrogate()) throw ProtocolFailure()
                            }
                        }
                        JsonToken.NUMBER -> NumberToken(reader.nextString())
                        else -> throw ProtocolFailure()
                    }
                }
                reader.endObject()
                return fields
            }
            val result = obj(1)
            if (reader.peek() != JsonToken.END_DOCUMENT) throw ProtocolFailure()
            return result
        } catch (e: ProtocolFailure) { throw e } catch (_: Exception) { throw ProtocolFailure() }
    }
    private fun identity(m: Map<String, Any>, budget: Long = 1): Request {
        fun id(key: String) = (m[key] as? String)?.takeIf { it.matches(Regex("[0-9a-f]{32}")) } ?: throw ProtocolFailure()
        val r = Request(id("request_id"), id("connection_id"), id("attempt_id"), budget)
        if (setOf(r.requestId, r.connectionId, r.attemptId).size != 3) throw ProtocolFailure()
        return r
    }
    private fun version(m: Map<String, Any>) {
        if (m["protocol_id"] != PROTOCOL || m["protocol_version"] != NumberToken("1"))
            throw ProtocolFailure("UnsupportedVersion", "Validate")
    }
    fun request(bytes: ByteArray): Request {
        if (bytes.size > REQUEST_CAP) throw ProtocolFailure("ResourceLimitExceeded")
        val m = parse(bytes)
        if (m.keys != setOf("protocol_id", "protocol_version", "request_id", "connection_id", "attempt_id", "remaining_budget_ms", "operation")) throw ProtocolFailure()
        version(m)
        val n = (m["remaining_budget_ms"] as? NumberToken)?.text ?: throw ProtocolFailure()
        if (!n.matches(Regex("[1-9][0-9]*"))) throw ProtocolFailure()
        val budget = n.toLongOrNull()?.takeIf { it <= 4294967295L } ?: throw ProtocolFailure()
        val result = identity(m, budget)
        val op = m["operation"] as? Map<*, *> ?: throw ProtocolFailure()
        val kind = op["kind"] as? String ?: throw ProtocolFailure()
        if (kind != "Readiness") throw ProtocolFailure("UnsupportedOperation", "Validate")
        if (op.keys != setOf("kind")) throw ProtocolFailure()
        return result
    }
    /** Only trustworthy IDs may be echoed when a request fails validation. */
    fun failureIdentity(bytes: ByteArray): Request? = try { identity(parse(bytes)) } catch (_: Exception) { null }
    fun cancel(bytes: ByteArray, request: Request) {
        if (bytes.size > CANCEL_CAP) throw ProtocolFailure("ResourceLimitExceeded", "Cancel")
        val m = parse(bytes)
        if (m.keys != setOf("protocol_id", "protocol_version", "request_id", "connection_id", "attempt_id", "control")) throw ProtocolFailure()
        version(m)
        val r = identity(m)
        if (r.copy(budget = request.budget) != request || m["control"] != "Cancel") throw ProtocolFailure()
    }
    fun readFrame(input: InputStream, cap: Int): ByteArray {
        val stream = DataInputStream(input)
        val length = stream.readInt().toLong() and 0xffffffffL
        if (length == 0L) throw ProtocolFailure()
        if (length > cap) throw ProtocolFailure("ResourceLimitExceeded")
        return ByteArray(length.toInt()).also { stream.readFully(it) }
    }
    fun writeFrame(output: OutputStream, bytes: ByteArray) {
        if (bytes.size > RESPONSE_CAP) throw ProtocolFailure("ResourceLimitExceeded", "Serialize")
        DataOutputStream(output).apply { writeInt(bytes.size); write(bytes); flush() }
    }
    fun response(r: Request, code: String?, stage: String, start: Long, finish: Long): ByteArray {
        val text = StringWriter()
        JsonWriter(text).apply {
            beginObject(); name("protocol_id").value(PROTOCOL); name("protocol_version").value(1)
            name("request_id").value(r.requestId); name("connection_id").value(r.connectionId); name("attempt_id").value(r.attemptId)
            name("outcome").beginObject()
            if (code == null) {
                name("kind").value("CompleteSuccess"); name("result").beginObject(); name("state").value("Ready"); endObject()
            } else { name("kind").value("Failure"); name("code").value(code); name("stage").value(stage) }
            endObject()
            if (code == null) { name("observer_started_elapsed_realtime_ms").value(start); name("observer_finished_elapsed_realtime_ms").value(finish) }
            endObject(); close()
        }
        return text.toString().toByteArray(Charsets.UTF_8).also { require(it.size <= RESPONSE_CAP) }
    }
}
