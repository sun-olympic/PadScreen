package app.padscreen.core

class ReconnectBackoff {
    private var next = 250L

    fun nextDelayMillis(): Long {
        val current = next
        next = (next * 2).coerceAtMost(5_000L)
        return current
    }

    fun reset() {
        next = 250L
    }
}

enum class ClientConnectionState {
    DISCONNECTED,
    CONNECTING,
    NEGOTIATING,
    STREAMING,
    ERROR,
}

class ClientStateMachine {
    var current: ClientConnectionState = ClientConnectionState.DISCONNECTED
        private set
    var detail: String = ""
        private set

    fun connecting() { current = ClientConnectionState.CONNECTING }
    fun negotiating() { current = ClientConnectionState.NEGOTIATING }
    fun streaming() { current = ClientConnectionState.STREAMING }
    fun disconnected(reason: String = "") {
        current = ClientConnectionState.DISCONNECTED
        detail = reason
    }
    fun failed(reason: String) {
        current = ClientConnectionState.ERROR
        detail = reason
    }
}

object TouchNormalizer {
    fun normalize(x: Float, y: Float, width: Int, height: Int): Pair<Double, Double> {
        require(width > 0 && height > 0)
        return Pair(
            (x / width).toDouble().coerceIn(0.0, 1.0),
            (y / height).toDouble().coerceIn(0.0, 1.0),
        )
    }
}

object H264AccessUnit {
    fun isKeyFrame(data: ByteArray): Boolean {
        var offset = 0
        while (offset + 3 < data.size) {
            val threeByteStart = data[offset] == 0.toByte() &&
                data[offset + 1] == 0.toByte() && data[offset + 2] == 1.toByte()
            val fourByteStart = offset + 4 < data.size && data[offset] == 0.toByte() &&
                data[offset + 1] == 0.toByte() && data[offset + 2] == 0.toByte() &&
                data[offset + 3] == 1.toByte()
            val headerOffset = when {
                fourByteStart -> offset + 4
                threeByteStart -> offset + 3
                else -> {
                    offset += 1
                    continue
                }
            }
            if (headerOffset < data.size && (data[headerOffset].toInt() and 0x1f) == 5) return true
            offset = headerOffset + 1
        }
        return false
    }
}

class DecoderInputScheduler(private val recoveryBacklogThreshold: Int = 4) {
    private val availableInputBuffers = ArrayDeque<Int>()
    private val pendingAccessUnits = ArrayDeque<ByteArray>()
    var droppedAccessUnitCount = 0
        private set

    @Synchronized
    fun offer(data: ByteArray) {
        if (H264AccessUnit.isKeyFrame(data) && pendingAccessUnits.size >= recoveryBacklogThreshold) {
            droppedAccessUnitCount += pendingAccessUnits.size
            pendingAccessUnits.clear()
        }
        pendingAccessUnits.addLast(data)
    }

    @Synchronized
    fun onInputBufferAvailable(index: Int) {
        availableInputBuffers.addLast(index)
    }

    @Synchronized
    fun takeReady(): Pair<Int, ByteArray>? {
        if (pendingAccessUnits.isEmpty() || availableInputBuffers.isEmpty()) return null
        return availableInputBuffers.removeFirst() to pendingAccessUnits.removeFirst()
    }

    @Synchronized
    fun pendingCount(): Int = pendingAccessUnits.size

    @Synchronized
    fun clear() {
        pendingAccessUnits.clear()
        availableInputBuffers.clear()
    }
}

class CodecConfigurationGate {
    private var lastConfiguration: ByteArray? = null

    fun shouldReconfigure(configuration: ByteArray): Boolean {
        if (lastConfiguration?.contentEquals(configuration) == true) return false
        lastConfiguration = configuration.copyOf()
        return true
    }
}

object AvcDecoderSelector {
    data class Candidate(val name: String, val hardwareAccelerated: Boolean)

    fun selectForInteractiveStreaming(candidates: List<Candidate>): String? =
        candidates.firstOrNull {
            !it.hardwareAccelerated && it.name.equals("c2.android.avc.decoder", ignoreCase = true)
        }?.name ?: selectCandidate(candidates)

    fun selectCandidate(candidates: List<Candidate>): String? =
        candidates.firstOrNull { it.hardwareAccelerated && it.name.contains("low_latency", ignoreCase = true) }?.name
            ?: candidates.firstOrNull { it.hardwareAccelerated }?.name
            ?: candidates.firstOrNull { it.name.contains("low_latency", ignoreCase = true) }?.name
            ?: candidates.firstOrNull()?.name

    fun select(decoderNames: List<String>): String? =
        selectCandidate(decoderNames.map { Candidate(it, !isSoftwareDecoderName(it)) })

    private fun isSoftwareDecoderName(name: String): Boolean =
        name.startsWith("c2.android.", ignoreCase = true) ||
            name.startsWith("omx.google.", ignoreCase = true) ||
            name.contains("software", ignoreCase = true)
}

object VideoSurfacePolicy {
    const val targetFrameRate = 90f
    const val frameDurationUs = 11_111L
    const val decoderOperatingRate = 180
}
