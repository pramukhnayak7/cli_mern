package com.example.prog_server

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "prog_server/background")
            .setMethodCallHandler { call, result ->
                if (call.method == "startForegroundService") {
                    val intent = Intent(this@MainActivity, BackgroundServerService::class.java)
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                        this@MainActivity.startForegroundService(intent)
                    } else {
                        this@MainActivity.startService(intent)
                    }
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }
    }
}
