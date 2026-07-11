package app.padscreen

import android.os.Bundle
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.SurfaceView
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.lifecycleScope
import app.padscreen.core.ClientConnectionState
import app.padscreen.core.H264SurfaceDecoder
import app.padscreen.core.PadScreenClient
import app.padscreen.core.PadScreenClientListener
import app.padscreen.core.TouchNormalizer
import app.padscreen.core.VideoSurfacePolicy

class MainActivity : ComponentActivity(), PadScreenClientListener {
    private val decoder = H264SurfaceDecoder()
    private lateinit var client: PadScreenClient
    private var state by mutableStateOf(ClientConnectionState.DISCONNECTED)
    private var detail by mutableStateOf("")
    private var host by mutableStateOf("192.168.1.2")

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        client = PadScreenClient(lifecycleScope, this)
        setContent {
            MaterialTheme {
                Box(Modifier.fillMaxSize().background(Color(0xFF090B10))) {
                    AndroidView(
                        modifier = Modifier.fillMaxSize(),
                        factory = { context -> createSurfaceView(context) },
                    )
                    if (state != ClientConnectionState.STREAMING) {
                        Column(
                            modifier = Modifier.align(Alignment.Center).padding(32.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(16.dp),
                        ) {
                            Text("PadScreen", color = Color.White, style = MaterialTheme.typography.headlineLarge)
                            Text(state.name + if (detail.isBlank()) "" else " · $detail", color = Color(0xFFB8C2D8))
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                OutlinedTextField(
                                    modifier = Modifier.weight(1f),
                                    value = host,
                                    onValueChange = { host = it },
                                    label = { Text("Mac IP") },
                                    singleLine = true,
                                )
                                Button(onClick = { client.connect(host.trim()) }) { Text("连接") }
                            }
                        }
                    }
                }
            }
        }
    }

    override fun onDestroy() {
        client.disconnect()
        decoder.release()
        super.onDestroy()
    }

    override fun onState(state: ClientConnectionState, detail: String) {
        runOnUiThread {
            this.state = state
            this.detail = detail
        }
    }

    override fun onCodecConfiguration(data: ByteArray) = decoder.configure(data)
    override fun onVideoAccessUnit(data: ByteArray) = decoder.queueAccessUnit(data)

    private fun createSurfaceView(context: android.content.Context): SurfaceView = SurfaceView(context).apply {
        holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) {
                holder.surface.setFrameRate(
                    VideoSurfacePolicy.targetFrameRate,
                    android.view.Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE,
                )
                decoder.setSurface(holder.surface)
            }
            override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) = Unit
            override fun surfaceDestroyed(holder: SurfaceHolder) = decoder.setSurface(null)
        })
        setOnTouchListener { view, event ->
            val (x, y) = TouchNormalizer.normalize(event.x, event.y, view.width, view.height)
            val action = when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> "down"
                MotionEvent.ACTION_MOVE -> "move"
                MotionEvent.ACTION_UP -> "up"
                MotionEvent.ACTION_CANCEL -> "cancel"
                else -> return@setOnTouchListener false
            }
            client.sendPointer(action, x, y)
            true
        }
    }
}
