package com.kepler.kepler_messenger

import android.os.Build
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kepler/sms").setMethodCallHandler { call, result ->
            if (call.method == "send") {
                try {
                    val phone = call.argument<String>("phone")!!
                    val text = call.argument<String>("text")!!
                    @Suppress("DEPRECATION")
                    val sms: SmsManager = if (Build.VERSION.SDK_INT >= 31) getSystemService(SmsManager::class.java) else SmsManager.getDefault()
                    val parts = sms.divideMessage(text)
                    sms.sendMultipartTextMessage(phone, null, parts, null, null)
                    result.success(true)
                } catch (e: Throwable) {
                    result.success(false)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
