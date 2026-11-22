package pe.arfit.arfit

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Actividad principal. Expone a Flutter el probador 3D de Snap Camera Kit:
 *   - vista nativa "pe.arfit/snap_camera" (SnapCameraView): la cámara con el
 *     lente de la prenda, incrustada en la misma pantalla que el probador 2D
 *   - canal "pe.arfit/snap_tryon": isAvailable (token y grupo de lentes configurados)
 */
class MainActivity : FlutterFragmentActivity() {

    private fun metaData(key: String): String? = try {
        packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
            .metaData?.getString(key)?.takeIf { it.isNotBlank() }
    } catch (e: Exception) {
        null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        flutterEngine.platformViewsController.registry.registerViewFactory(
            "pe.arfit/snap_camera",
            SnapCameraFactory(this, messenger) { metaData("pe.arfit.snap.lens_group") },
        )

        MethodChannel(messenger, "pe.arfit/snap_tryon").setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(
                    metaData("com.snap.camerakit.api.token") != null && metaData("pe.arfit.snap.lens_group") != null
                )
                else -> result.notImplemented()
            }
        }
    }
}
