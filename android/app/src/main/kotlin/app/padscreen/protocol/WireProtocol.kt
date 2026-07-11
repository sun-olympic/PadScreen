package app.padscreen.protocol

import java.nio.ByteBuffer
import java.nio.ByteOrder

enum class MessageType(val code: Int) {
    HELLO(1),
    SESSION(2),
    CODEC_CONFIGURATION(3),
    VIDEO(4),
    INPUT(5),
    HEARTBEAT(6),
    ERROR(7);

    companion object {
        fun fromCode(code: Int): MessageType? = entries.firstOrNull { it.code == code }
    }
}

data class WireFrame(val type: MessageType, val payload: ByteArray) {
    override fun equals(other: Any?): Boolean =
        other is WireFrame && type == other.type && payload.contentEquals(other.payload)

    override fun hashCode(): Int = 31 * type.hashCode() + payload.contentHashCode()
}

sealed class ProtocolException(message: String) : Exception(message) {
    class InvalidMagic : ProtocolException("Invalid PDS1 magic")
    class UnsupportedVersion(val version: Int) : ProtocolException("Unsupported protocol version: $version")
    class UnknownMessageType(val code: Int) : ProtocolException("Unknown message type: $code")
    class PayloadTooLarge(val size: Int) : ProtocolException("Payload exceeds configured maximum: $size")
}

object FrameCodec {
    const val VERSION = 1
    const val HEADER_SIZE = 12
    private val magic = byteArrayOf(0x50, 0x44, 0x53, 0x31)

    fun encode(frame: WireFrame): ByteArray {
        val output = ByteBuffer.allocate(HEADER_SIZE + frame.payload.size).order(ByteOrder.BIG_ENDIAN)
        output.put(magic)
        output.put(VERSION.toByte())
        output.put(frame.type.code.toByte())
        output.putShort(0)
        output.putInt(frame.payload.size)
        output.put(frame.payload)
        return output.array()
    }
}

class FrameDecoder(private val maxPayloadSize: Int = 16 * 1024 * 1024) {
    private var buffer = byteArrayOf()

    fun append(bytes: ByteArray): List<WireFrame> {
        buffer += bytes
        val frames = mutableListOf<WireFrame>()

        while (buffer.size >= FrameCodec.HEADER_SIZE) {
            if (!buffer.copyOfRange(0, 4).contentEquals(byteArrayOf(0x50, 0x44, 0x53, 0x31))) {
                throw ProtocolException.InvalidMagic()
            }
            val version = buffer[4].toInt() and 0xff
            if (version != FrameCodec.VERSION) throw ProtocolException.UnsupportedVersion(version)
            val rawType = buffer[5].toInt() and 0xff
            val type = MessageType.fromCode(rawType) ?: throw ProtocolException.UnknownMessageType(rawType)
            val payloadSize = ByteBuffer.wrap(buffer, 8, 4).order(ByteOrder.BIG_ENDIAN).int
            if (payloadSize < 0 || payloadSize > maxPayloadSize) {
                throw ProtocolException.PayloadTooLarge(payloadSize)
            }
            val frameSize = FrameCodec.HEADER_SIZE + payloadSize
            if (buffer.size < frameSize) break

            frames += WireFrame(type, buffer.copyOfRange(FrameCodec.HEADER_SIZE, frameSize))
            buffer = buffer.copyOfRange(frameSize, buffer.size)
        }

        return frames
    }
}
