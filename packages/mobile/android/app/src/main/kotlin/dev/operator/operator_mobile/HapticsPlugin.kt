package dev.operator.operator_mobile

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

object HapticsPlugin {
    fun register(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, "operator/haptics").setMethodCallHandler { call, result ->
            if (call.method != "notify") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            // Android has no notification-feedback API. The predefined effects are the
            // closest stock patterns: DOUBLE_CLICK reads as an affirmative, HEAVY_CLICK
            // as a caution, and TICK-then-HEAVY as a rejection.
            val effect = when (call.arguments as? String) {
                "success" -> VibrationEffect.EFFECT_DOUBLE_CLICK
                "warning" -> VibrationEffect.EFFECT_HEAVY_CLICK
                "error" -> VibrationEffect.EFFECT_DOUBLE_CLICK
                else -> {
                    result.error("bad_arg", "unknown kind ${call.arguments}", null)
                    return@setMethodCallHandler
                }
            }
            vibrator(context)?.takeIf { it.hasVibrator() }?.let { device ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    device.vibrate(VibrationEffect.createPredefined(effect))
                }
            }
            result.success(null)
        }
    }

    private fun vibrator(context: Context): Vibrator? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
                ?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
}
