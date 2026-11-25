package com.example.vocab_overlay

import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "vocab_overlay/app"
    private val tag = "vocab_overlay/app"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // 把主应用移到后台，让系统悬浮窗显示在其他应用之上。
                    "moveToBackground" -> {
                        // 用 false 而非 true：true 会要求"同一个 task 里还有其它
                        // activity"才移动，某些 ROM 上会导致不动；false 更稳。
                        val moved = moveTaskToBack(false)
                        Log.i(tag, "moveToBackground moved=$moved")
                        result.success(moved)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
