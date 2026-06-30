package com.example.cctv

import io.flutter.embedding.android.FlutterActivity

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "camera_sdk"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "connectCamera") {
                val uid = call.argument<String>("uid")
                val username = call.argument<String>("username")
                val password = call.argument<String>("password")

                if (uid.isNullOrEmpty() || username.isNullOrEmpty() || password.isNullOrEmpty()) {
                    result.error("INVALID_ARGUMENTS", "UID, Username, and Password must not be empty", null)
                } else {
                    // Simulate vendor SDK login
                    println("[CameraSDK] Simulating SDK Login...")
                    println("[CameraSDK] UID: $uid")
                    println("[CameraSDK] Username: $username")
                    
                    // Respond with success
                    result.success(true)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
