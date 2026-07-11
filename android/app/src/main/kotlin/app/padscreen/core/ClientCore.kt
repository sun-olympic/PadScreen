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

class DecoderInputScheduler {
    private val availableInputBuffers = ArrayDeque<Int>()
    private val pendingAccessUnits = ArrayDeque<ByteArray>()

    @Synchronized
    fun offer(data: ByteArray) {
        pendingAccessUnits.addLast(data.copyOf())
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
    fun select(decoderNames: List<String>): String? =
        decoderNames.firstOrNull { it.contains("avc.decoder.low_latency", ignoreCase = true) }
            ?: decoderNames.firstOrNull()
}

object VideoSurfacePolicy {
    const val targetFrameRate = 120f
    const val frameDurationUs = 8_333L
    const val decoderOperatingRate = 240
}
