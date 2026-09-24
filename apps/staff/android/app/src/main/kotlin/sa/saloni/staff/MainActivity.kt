package sa.saloni.staff

import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // ق40 (مراجعة F1): الوقت المنقضي منذ تشغيل الجهاز (يشمل النوم ولا يتأثر بتغيير
        // الساعة) مع عدّاد مرات التشغيل — لحساب وقت إغلاق التطبيق بدقة عند إعادة فتحه.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "saloni/boot_clock")
            .setMethodCallHandler { call, result ->
                if (call.method != "read") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val bootCount: Int? =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        try {
                            Settings.Global.getInt(contentResolver, Settings.Global.BOOT_COUNT)
                        } catch (e: Exception) {
                            null
                        }
                    } else {
                        null
                    }
                result.success(
                    mapOf(
                        "sinceBootMs" to SystemClock.elapsedRealtime(),
                        "bootId" to bootCount?.toString(),
                    ),
                )
            }
    }
}
