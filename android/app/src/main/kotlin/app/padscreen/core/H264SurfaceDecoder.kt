package app.padscreen.core

import android.media.MediaCodec
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.Handler
import android.os.HandlerThread
import android.os.Process
import android.util.Log
import android.view.Surface
import java.nio.ByteBuffer

class H264SurfaceDecoder {
    private val decoderThread = HandlerThread("PadScreenDecoder", Process.THREAD_PRIORITY_DISPLAY).apply { start() }
    private val handler = Handler(decoderThread.looper)
    private val inputScheduler = DecoderInputScheduler()
    private val configurationGate = CodecConfigurationGate()
    private var surface: Surface? = null
    private var codecConfiguration: ByteArray? = null
    private var codec: MediaCodec? = null
    private var presentationTimeUs = 0L
    private var queuedInputCount = 0L
    private var renderedOutputCount = 0L
    private val idleTelemetry = Runnable {
        Log.i(
            "PadScreenDecoder",
            "idle queued=$queuedInputCount rendered=$renderedOutputCount " +
                "inFlight=${queuedInputCount - renderedOutputCount} pending=${inputScheduler.pendingCount()}",
        )
    }

    fun setSurface(newSurface: Surface?) {
        handler.post {
            surface = newSurface
            reconfigure()
        }
    }

    fun configure(data: ByteArray) {
        handler.post {
            if (!configurationGate.shouldReconfigure(data)) return@post
            Log.i("PadScreenDecoder", "codecConfiguration=${data.joinToString("") { "%02x".format(it) }}")
            codecConfiguration = data.copyOf()
            reconfigure()
        }
    }

    fun queueAccessUnit(data: ByteArray) {
        inputScheduler.offer(data)
        handler.post {
            feedPendingAccessUnit()
            handler.removeCallbacks(idleTelemetry)
            handler.postDelayed(idleTelemetry, 500)
        }
    }

    fun release() {
        handler.post {
            stopCodec()
            surface = null
            decoderThread.quitSafely()
        }
    }

    private fun feedPendingAccessUnit() {
        val decoder = codec ?: return
        val (inputIndex, data) = inputScheduler.takeReady() ?: return
        val inputBuffer = decoder.getInputBuffer(inputIndex)
        if (inputBuffer == null) {
            inputScheduler.offer(data)
            inputScheduler.onInputBufferAvailable(inputIndex)
            return
        }
        inputBuffer.apply {
            clear()
            put(data)
        }
        presentationTimeUs += VideoSurfacePolicy.frameDurationUs
        decoder.queueInputBuffer(inputIndex, 0, data.size, presentationTimeUs, 0)
        queuedInputCount += 1
    }

    private fun reconfigure() {
        stopCodec()
        val target = surface ?: return
        val config = codecConfiguration ?: return
        val decoderCandidates = MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos
            .filter { !it.isEncoder && it.supportedTypes.any { type -> type.equals(MediaFormat.MIMETYPE_VIDEO_AVC, true) } }
            .map { AvcDecoderSelector.Candidate(it.name, it.isHardwareAccelerated) }
        val decoderName = AvcDecoderSelector.selectForInteractiveStreaming(decoderCandidates)
        Log.i("PadScreenDecoder", "selectedDecoder=$decoderName")
        val decoder = decoderName?.let(MediaCodec::createByCodecName)
            ?: MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        decoder.setCallback(object : MediaCodec.Callback() {
            override fun onInputBufferAvailable(callbackCodec: MediaCodec, index: Int) {
                if (codec !== callbackCodec) return
                inputScheduler.onInputBufferAvailable(index)
                feedPendingAccessUnit()
            }

            override fun onOutputBufferAvailable(
                callbackCodec: MediaCodec,
                index: Int,
                info: MediaCodec.BufferInfo,
            ) {
                if (codec === callbackCodec) {
                    callbackCodec.releaseOutputBuffer(index, true)
                    renderedOutputCount += 1
                    if (renderedOutputCount % 90L == 0L) {
                        Log.i(
                            "PadScreenDecoder",
                            "running queued=$queuedInputCount rendered=$renderedOutputCount " +
                                "inFlight=${queuedInputCount - renderedOutputCount} " +
                                "pending=${inputScheduler.pendingCount()}",
                        )
                    }
                    feedPendingAccessUnit()
                }
            }

            override fun onOutputFormatChanged(callbackCodec: MediaCodec, format: MediaFormat) = Unit

            override fun onError(callbackCodec: MediaCodec, error: MediaCodec.CodecException) {
                if (codec === callbackCodec) stopCodec()
            }
        }, handler)
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, 1920, 1200).apply {
            setByteBuffer("csd-0", ByteBuffer.wrap(config))
            setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
            setInteger(MediaFormat.KEY_FRAME_RATE, VideoSurfacePolicy.targetFrameRate.toInt())
            setInteger(MediaFormat.KEY_OPERATING_RATE, VideoSurfacePolicy.decoderOperatingRate)
            setInteger(MediaFormat.KEY_PRIORITY, 0)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 2 * 1024 * 1024)
        }
        decoder.configure(format, target, null, 0)
        codec = decoder
        presentationTimeUs = 0
        queuedInputCount = 0
        renderedOutputCount = 0
        decoder.start()
    }

    private fun stopCodec() {
        val decoder = codec
        codec = null
        handler.removeCallbacks(idleTelemetry)
        inputScheduler.clear()
        queuedInputCount = 0
        renderedOutputCount = 0
        decoder?.let {
            runCatching { decoder.stop() }
            decoder.release()
        }
    }
}
