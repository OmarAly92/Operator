package dev.operator.operator_mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        HapticsPlugin.register(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }
}
