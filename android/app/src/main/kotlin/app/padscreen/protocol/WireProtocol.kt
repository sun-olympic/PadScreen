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
    private var buffer = ByteArray(64 * 1024)
    private var readOffset = 0
    private var writeOffset = 0

    fun append(bytes: ByteArray): List<WireFrame> = append(bytes, bytes.size)

    fun append(bytes: ByteArray, length: Int): List<WireFrame> {
        require(length in 0..bytes.size)
        ensureWritable(length)
        bytes.copyInto(buffer, writeOffset, 0, length)
        writeOffset += length
        val frames = mutableListOf<WireFrame>()

        while (writeOffset - readOffset >= FrameCodec.HEADER_SIZE) {
            if (buffer[readOffset] != 0x50.toByte() ||
                buffer[readOffset + 1] != 0x44.toByte() ||
                buffer[readOffset + 2] != 0x53.toByte() ||
                buffer[readOffset + 3] != 0x31.toByte()
            ) {
                throw ProtocolException.InvalidMagic()
            }
            val version = buffer[readOffset + 4].toInt() and 0xff
            if (version != FrameCodec.VERSION) throw ProtocolException.UnsupportedVersion(version)
            val rawType = buffer[readOffset + 5].toInt() and 0xff
            val type = MessageType.fromCode(rawType) ?: throw ProtocolException.UnknownMessageType(rawType)
            val payloadSize = ((buffer[readOffset + 8].toInt() and 0xff) shl 24) or
                ((buffer[readOffset + 9].toInt() and 0xff) shl 16) or
                ((buffer[readOffset + 10].toInt() and 0xff) shl 8) or
                (buffer[readOffset + 11].toInt() and 0xff)
            if (payloadSize < 0 || payloadSize > maxPayloadSize) {
                throw ProtocolException.PayloadTooLarge(payloadSize)
            }
            val frameSize = FrameCodec.HEADER_SIZE + payloadSize
            if (writeOffset - readOffset < frameSize) break

            val payloadStart = readOffset + FrameCodec.HEADER_SIZE
            frames += WireFrame(type, buffer.copyOfRange(payloadStart, payloadStart + payloadSize))
            readOffset += frameSize
        }

        compactIfUseful()
        return frames
    }

    private fun ensureWritable(additionalBytes: Int) {
        if (buffer.size - writeOffset >= additionalBytes) return
        val unreadBytes = writeOffset - readOffset
        if (buffer.size - unreadBytes >= additionalBytes) {
            buffer.copyInto(buffer, 0, readOffset, writeOffset)
            readOffset = 0
            writeOffset = unreadBytes
            return
        }

        var capacity = buffer.size
        val required = unreadBytes + additionalBytes
        while (capacity < required) capacity = (capacity * 2).coerceAtLeast(required)
        val replacement = ByteArray(capacity)
        buffer.copyInto(replacement, 0, readOffset, writeOffset)
        buffer = replacement
        readOffset = 0
        writeOffset = unreadBytes
    }

    private fun compactIfUseful() {
        if (readOffset == writeOffset) {
            readOffset = 0
            writeOffset = 0
        } else if (readOffset >= buffer.size / 2) {
            val unreadBytes = writeOffset - readOffset
            buffer.copyInto(buffer, 0, readOffset, writeOffset)
            readOffset = 0
            writeOffset = unreadBytes
        }
    }
}
