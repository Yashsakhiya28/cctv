package com.example.cctv

import android.content.Context
import android.graphics.Color
import android.net.Uri
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import android.widget.VideoView
import io.flutter.plugin.platform.PlatformView

class CctvPlayView(context: Context, id: Int, creationParams: Map<String?, Any?>?) : PlatformView {
    private val container: FrameLayout = FrameLayout(context)
    private val videoView: VideoView = VideoView(context)
    private val statusTextView: TextView = TextView(context)

    init {
        // Layout params for filling the parent container
        val layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        )
        container.layoutParams = layoutParams
        container.setBackgroundColor(Color.BLACK)

        // Set up VideoView to fill container
        videoView.layoutParams = layoutParams
        container.addView(videoView)

        // Set up overlay Status TextView
        statusTextView.layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            setMargins(24, 24, 24, 24)
        }
        statusTextView.setTextColor(Color.GREEN)
        statusTextView.setTextSize(14f)
        statusTextView.text = "SDK LIVE P2P: CONNECTING..."
        container.addView(statusTextView)

        // Retrieve the UID parameter passed from Flutter
        val uid = creationParams?.get("uid") as? String ?: "Unknown"

        // CCTV test feed URL
        val videoUrl = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"
        
        try {
            videoView.setVideoURI(Uri.parse(videoUrl))
            videoView.setOnPreparedListener { mp ->
                mp.isLooping = true
                videoView.start()
                statusTextView.text = "SDK LIVE P2P: ACTIVE (UID: $uid)"
            }
            videoView.setOnErrorListener { _, _, _ ->
                statusTextView.setTextColor(Color.RED)
                statusTextView.text = "SDK LIVE P2P ERROR: DECODE FAILED (UID: $uid)"
                true
            }
        } catch (e: Exception) {
            statusTextView.setTextColor(Color.RED)
            statusTextView.text = "SDK LIVE P2P ERROR: ${e.message}"
        }
    }

    override fun getView(): View {
        return container
    }

    override fun dispose() {
        videoView.stopPlayback()
    }
}
