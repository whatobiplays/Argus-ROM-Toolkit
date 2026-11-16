package com.argusromtoolkit.argus.readinessprobe

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [30])
class ReadinessProtocolTest {
    private val ids = "\"request_id\":\"${"a".repeat(32)}\",\"connection_id\":\"${"b".repeat(32)}\",\"attempt_id\":\"${"c".repeat(32)}\""
    private fun request(operation: String = "{\"kind\":\"Readiness\"}") =
        "{\"protocol_id\":\"argus.product-observer\",\"protocol_version\":1,$ids,\"remaining_budget_ms\":5000,\"operation\":$operation}"
    @Test fun closedReadinessIsDecodedAndSuccessFitsCap() {
        val request = ReadinessProtocol.request(request().toByteArray())
        val response = ReadinessProtocol.response(request, null, "Read", 1, 2)
        assertTrue(response.size <= 393)
        assertTrue(String(response).contains("\"state\":\"Ready\""))
        assertTrue(String(response).contains("observer_finished_elapsed_realtime_ms"))
    }
    @Test fun rejectsDuplicateUnknownCoercedAndTrailingFields() {
        for (body in listOf(request().replace("5000", "5e3"), request().replace("5000", "\"5000\""),
            request().replace("5000", "0"), request().dropLast(1) + ",\"extra\":1}",
            request().replace("5000", "5000,\"remaining_budget_ms\":1"), request() + "{}")) {
            assertThrows(ProtocolFailure::class.java) { ReadinessProtocol.request(body.toByteArray()) }
        }
    }
    @Test fun rejectsUnsupportedOperationWithoutInventingWireCode() {
        val error = assertThrows(ProtocolFailure::class.java) {
            ReadinessProtocol.request(request("{\"kind\":\"GetJob\"}").toByteArray())
        }
        assertEquals("UnsupportedOperation", error.code)
    }
    @Test fun cancellationMustMatchAllIdentities() {
        val request = ReadinessProtocol.request(request().toByteArray())
        val cancel = "{\"protocol_id\":\"argus.product-observer\",\"protocol_version\":1,$ids,\"control\":\"Cancel\"}"
        ReadinessProtocol.cancel(cancel.toByteArray(), request)
        assertThrows(ProtocolFailure::class.java) {
            ReadinessProtocol.cancel(cancel.replace("c".repeat(32), "d".repeat(32)).toByteArray(), request)
        }
    }

    @Test fun framingRejectsOversizedUnsignedLengthsBeforeReadingBody() {
        val input = object : java.io.InputStream() {
            var index = 0
            override fun read(): Int { if (index++ < 4) return 255; error("Body must not be read") }
        }
        val failure = assertThrows(ProtocolFailure::class.java) { ReadinessProtocol.readFrame(input, 274) }
        assertEquals("ResourceLimitExceeded", failure.code)
        assertThrows(ProtocolFailure::class.java) { ReadinessProtocol.readFrame(java.io.ByteArrayInputStream(ByteArray(4)), 274) }
    }
    @Test fun malformedUtf8AndUnpairedSurrogateCannotBeAccepted() {
        assertThrows(ProtocolFailure::class.java) { ReadinessProtocol.request(byteArrayOf(0xc3.toByte(), 0x28)) }
        val invalid = request().replace("Readiness", "\\ud800")
        assertThrows(ProtocolFailure::class.java) { ReadinessProtocol.request(invalid.toByteArray()) }
    }
    @Test fun failureContainsNoSuccessFacts() {
        val r = ReadinessProtocol.request(request().toByteArray())
        val body = String(ReadinessProtocol.response(r, "Cancelled", "Cancel", 1, 2))
        assertFalse(body.contains("elapsed_realtime")); assertFalse(body.contains("result"))
        assertTrue(body.contains("Cancelled"))
    }
}
