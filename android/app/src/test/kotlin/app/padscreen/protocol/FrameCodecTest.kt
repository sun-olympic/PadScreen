package app.padscreen.protocol

import app.padscreen.core.ClientConnectionState
import app.padscreen.core.ClientStateMachine
import app.padscreen.core.CodecConfigurationGate
import app.padscreen.core.AvcDecoderSelector
import app.padscreen.core.H264AccessUnit
import app.padscreen.core.ReconnectBackoff
import app.padscreen.core.TouchNormalizer
import java.util.HexFormat

private fun assertTrue(value: Boolean, message: String) {
    if (!value) error(message)
}

private inline fun <reified T : Throwable> assertThrows(block: () -> Unit) {
    try {
        block()
        error("Expected ${T::class.simpleName}")
    } catch (error: Throwable) {
        if (error !is T) throw error
    }
}

fun main() {
    val heartbeat = FrameCodec.encode(WireFrame(MessageType.HEARTBEAT, byteArrayOf()))
    assertTrue(
        HexFormat.of().formatHex(heartbeat) == "504453310106000000000000",
        "heartbeat must match Swift golden vector",
    )

    val payload = "{\"width\":1920}".encodeToByteArray()
    val encoded = FrameCodec.encode(WireFrame(MessageType.HELLO, payload))
    val decoder = FrameDecoder()
    assertTrue(decoder.append(encoded.copyOfRange(0, 5)).isEmpty(), "partial header emitted a frame")
    assertTrue(decoder.append(encoded.copyOfRange(5, 13)).isEmpty(), "partial payload emitted a frame")
    val frames = decoder.append(encoded.copyOfRange(13, encoded.size))
    assertTrue(frames.size == 1, "incremental frame was not emitted")
    assertTrue(frames.single().type == MessageType.HELLO, "message type changed")
    assertTrue(frames.single().payload.contentEquals(payload), "payload changed")

    val first = FrameCodec.encode(WireFrame(MessageType.HEARTBEAT, byteArrayOf()))
    val second = FrameCodec.encode(WireFrame(MessageType.ERROR, "oops".encodeToByteArray()))
    val combined = FrameDecoder().append(first + second)
    assertTrue(combined.map { it.type } == listOf(MessageType.HEARTBEAT, MessageType.ERROR), "multi-frame read failed")

    val reusableReadBuffer = encoded + byteArrayOf(99, 98, 97)
    val countedFrames = FrameDecoder().append(reusableReadBuffer, encoded.size)
    assertTrue(countedFrames.single().payload.contentEquals(payload), "counted socket read included stale bytes")

    assertThrows<ProtocolException.InvalidMagic> {
        FrameDecoder().append(byteArrayOf(0, 0, 0, 0, 1, 6, 0, 0, 0, 0, 0, 0))
    }
    assertThrows<ProtocolException.PayloadTooLarge> {
        FrameDecoder(maxPayloadSize = 3).append(
            byteArrayOf(0x50, 0x44, 0x53, 0x31, 1, 4, 0, 0, 0, 0, 0, 4),
        )
    }

    val backoff = ReconnectBackoff()
    assertTrue(
        List(6) { backoff.nextDelayMillis() } == listOf(250L, 500L, 1_000L, 2_000L, 4_000L, 5_000L),
        "reconnect backoff is not bounded",
    )
    backoff.reset()
    assertTrue(backoff.nextDelayMillis() == 250L, "backoff did not reset")

    val state = ClientStateMachine()
    state.connecting()
    state.negotiating()
    state.streaming()
    assertTrue(state.current == ClientConnectionState.STREAMING, "valid state transitions failed")
    state.disconnected("socket closed")
    assertTrue(state.current == ClientConnectionState.DISCONNECTED, "disconnect transition failed")

    val normalized = TouchNormalizer.normalize(x = 1280f, y = 800f, width = 2560, height = 1600)
    assertTrue(normalized.first == 0.5 && normalized.second == 0.5, "touch normalization failed")

    val codecGate = CodecConfigurationGate()
    assertTrue(codecGate.shouldReconfigure(byteArrayOf(1, 2)), "first codec configuration was ignored")
    assertTrue(!codecGate.shouldReconfigure(byteArrayOf(1, 2)), "identical codec configuration caused a reset")
    assertTrue(codecGate.shouldReconfigure(byteArrayOf(1, 3)), "changed codec configuration was ignored")

    val selectedDecoder = AvcDecoderSelector.select(
        listOf("c2.qti.avc.decoder", "c2.android.avc.decoder", "c2.qti.avc.decoder.low_latency"),
    )
    assertTrue(selectedDecoder == "c2.qti.avc.decoder.low_latency", "low-latency AVC decoder was not preferred")
    val hardwareDecoder = AvcDecoderSelector.select(
        listOf("c2.android.avc.decoder", "c2.qti.avc.decoder"),
    )
    assertTrue(hardwareDecoder == "c2.qti.avc.decoder", "software AVC decoder was preferred over hardware")
    val interactiveDecoder = AvcDecoderSelector.selectForInteractiveStreaming(
        listOf(
            AvcDecoderSelector.Candidate("c2.qti.avc.decoder.low_latency", true),
            AvcDecoderSelector.Candidate("c2.android.avc.decoder", false),
        ),
    )
    assertTrue(interactiveDecoder == "c2.android.avc.decoder", "interactive streaming did not avoid buffered hardware AVC")

    val pFrame = byteArrayOf(0, 0, 0, 1, 0x41)
    val idrFrame = byteArrayOf(0, 0, 0, 1, 0x65)
    assertTrue(!H264AccessUnit.isKeyFrame(pFrame), "P-frame was classified as a keyframe")
    assertTrue(H264AccessUnit.isKeyFrame(idrFrame), "IDR frame was not classified as a keyframe")

    val targetSurfaceFrameRate = runCatching {
        Class.forName("app.padscreen.core.VideoSurfacePolicy")
            .getField("targetFrameRate")
            .getFloat(null)
    }.getOrNull()
    assertTrue(targetSurfaceFrameRate == 90f, "video Surface did not declare the stable 90 fps source cadence")

    val scheduledInputs = runCatching {
        val type = Class.forName("app.padscreen.core.DecoderInputScheduler")
        val scheduler = type.getConstructor().newInstance()
        type.getMethod("offer", ByteArray::class.java).invoke(scheduler, byteArrayOf(1))
        type.getMethod("offer", ByteArray::class.java).invoke(scheduler, byteArrayOf(2))
        type.getMethod("onInputBufferAvailable", Int::class.javaPrimitiveType).invoke(scheduler, 7)
        type.getMethod("onInputBufferAvailable", Int::class.javaPrimitiveType).invoke(scheduler, 8)
        val first = type.getMethod("takeReady").invoke(scheduler) as Pair<*, *>
        val second = type.getMethod("takeReady").invoke(scheduler) as Pair<*, *>
        first to second
    }.getOrNull()
    assertTrue(
        scheduledInputs?.first?.first == 7 &&
            (scheduledInputs.first.second as ByteArray).contentEquals(byteArrayOf(1)) &&
            scheduledInputs.second.first == 8 &&
            (scheduledInputs.second.second as ByteArray).contentEquals(byteArrayOf(2)),
        "decoder input callback did not preserve H.264 reference-frame order",
    )

    val recoveredInput = runCatching {
        val type = Class.forName("app.padscreen.core.DecoderInputScheduler")
        val scheduler = type.getConstructor(Int::class.javaPrimitiveType).newInstance(2)
        type.getMethod("offer", ByteArray::class.java).invoke(scheduler, pFrame + byteArrayOf(1))
        type.getMethod("offer", ByteArray::class.java).invoke(scheduler, pFrame + byteArrayOf(2))
        type.getMethod("offer", ByteArray::class.java).invoke(scheduler, idrFrame)
        type.getMethod("onInputBufferAvailable", Int::class.javaPrimitiveType).invoke(scheduler, 9)
        type.getMethod("takeReady").invoke(scheduler) as Pair<*, *>
    }.getOrNull()
    assertTrue(
        recoveredInput?.first == 9 && (recoveredInput.second as ByteArray).contentEquals(idrFrame),
        "decoder backlog did not recover at the next IDR frame",
    )

    println("Kotlin protocol and client-core tests passed")
}
