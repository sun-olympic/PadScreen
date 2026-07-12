package app.padscreen.core

import app.padscreen.protocol.FrameCodec
import app.padscreen.protocol.FrameDecoder
import app.padscreen.protocol.MessageType
import app.padscreen.protocol.WireFrame
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.Executors
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

interface PadScreenClientListener {
    fun onState(state: ClientConnectionState, detail: String = "")
    fun onCodecConfiguration(data: ByteArray)
    fun onVideoAccessUnit(data: ByteArray)
}

class PadScreenClient(
    private val scope: CoroutineScope,
    private val listener: PadScreenClientListener,
) {
    private val outputLock = Any()
    private val pointerExecutor = Executors.newSingleThreadExecutor()
    private var job: Job? = null
    @Volatile private var socket: Socket? = null
    @Volatile private var output: BufferedOutputStream? = null

    fun connect(host: String, port: Int = 48_596, width: Int = 2560, height: Int = 1600, density: Double = 2.0) {
        disconnect()
        job = scope.launch(Dispatchers.IO) {
            val backoff = ReconnectBackoff()
            while (isActive) {
                try {
                    listener.onState(ClientConnectionState.CONNECTING, "$host:$port")
                    val activeSocket = Socket().apply {
                        tcpNoDelay = true
                        keepAlive = true
                        receiveBufferSize = 256 * 1024
                        runCatching { trafficClass = 0x10 }
                        connect(InetSocketAddress(host, port), 3_000)
                    }
                    socket = activeSocket
                    output = BufferedOutputStream(activeSocket.getOutputStream())
                    listener.onState(ClientConnectionState.NEGOTIATING)
                    sendHello(width, height, density)
                    backoff.reset()
                    readLoop(activeSocket)
                } catch (error: Exception) {
                    listener.onState(ClientConnectionState.DISCONNECTED, error.message ?: "连接断开")
                } finally {
                    closeSocket()
                }
                delay(backoff.nextDelayMillis())
            }
        }
    }

    fun disconnect() {
        job?.cancel()
        job = null
        closeSocket()
        listener.onState(ClientConnectionState.DISCONNECTED)
    }

    fun sendPointer(action: String, x: Double, y: Double, deltaX: Double = 0.0, deltaY: Double = 0.0) {
        val json = JSONObject()
            .put("action", action)
            .put("normalizedX", x)
            .put("normalizedY", y)
            .put("deltaX", deltaX)
            .put("deltaY", deltaY)
        val frame = WireFrame(MessageType.INPUT, json.toString().encodeToByteArray())
        pointerExecutor.execute { send(frame) }
    }

    private fun sendHello(width: Int, height: Int, density: Double) {
        val json = JSONObject()
            .put("viewportWidth", width)
            .put("viewportHeight", height)
            .put("density", density)
            .put("codecs", JSONArray().put("h264"))
        send(WireFrame(MessageType.HELLO, json.toString().encodeToByteArray()))
    }

    private fun readLoop(activeSocket: Socket) {
        val input = BufferedInputStream(activeSocket.getInputStream(), 64 * 1024)
        val decoder = FrameDecoder()
        val chunk = ByteArray(64 * 1024)
        while (true) {
            val count = input.read(chunk)
            if (count < 0) return
            for (frame in decoder.append(chunk, count)) {
                when (frame.type) {
                    MessageType.SESSION -> listener.onState(ClientConnectionState.STREAMING)
                    MessageType.CODEC_CONFIGURATION -> listener.onCodecConfiguration(frame.payload)
                    MessageType.VIDEO -> listener.onVideoAccessUnit(frame.payload)
                    MessageType.HEARTBEAT -> Unit
                    MessageType.ERROR -> throw IllegalStateException(frame.payload.decodeToString())
                    else -> Unit
                }
            }
        }
    }

    private fun send(frame: WireFrame) {
        val bytes = FrameCodec.encode(frame)
        synchronized(outputLock) {
            output?.apply {
                write(bytes)
                flush()
            }
        }
    }

    private fun closeSocket() {
        synchronized(outputLock) {
            runCatching { output?.close() }
            output = null
            runCatching { socket?.close() }
            socket = null
        }
    }
}
