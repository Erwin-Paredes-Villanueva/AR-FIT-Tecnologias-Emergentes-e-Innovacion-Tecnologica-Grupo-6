package pe.arfit.arfit

import android.content.pm.PackageManager
import com.snap.camerakit.support.app.CameraActivity
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Actividad principal. Expone a Flutter el probador 3D de Snap Camera Kit
 * (canal "pe.arfit/snap_tryon"): abre la cámara de Snap con el lente de la prenda,
 * que trae seguimiento corporal 3D y simulación de tela.
 */
class MainActivity : FlutterFragmentActivity() {

    private var pendingResult: MethodChannel.Result? = null

    private val snapLauncher = registerForActivityResult(CameraActivity.Capture) { result ->
        val reply = when (result) {
            is CameraActivity.Capture.Result.Success.Image -> mapOf("status" to "image", "uri" to result.uri.toString())
            is CameraActivity.Capture.Result.Success.Video -> mapOf("status" to "video", "uri" to result.uri.toString())
            is CameraActivity.Capture.Result.Cancelled -> mapOf("status" to "cancelled")
            is CameraActivity.Capture.Result.Failure -> mapOf("status" to "failure", "error" to result.exception.toString())
            else -> mapOf("status" to "cancelled")
        }
        pendingResult?.success(reply)
        pendingResult = null
    }

    private fun metaData(key: String): String? = try {
        packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
            .metaData?.getString(key)?.takeIf { it.isNotBlank() }
    } catch (e: Exception) {
        null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pe.arfit/snap_tryon").setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(
                    metaData("com.snap.camerakit.api.token") != null && metaData("pe.arfit.snap.lens_group") != null
                )
                "launch" -> {
                    val groupId = metaData("pe.arfit.snap.lens_group")
                    val lensId = call.argument<String>("lensId")
                    if (groupId == null || metaData("com.snap.camerakit.api.token") == null) {
                        result.error("not_configured", "Falta configurar Snap Camera Kit", null)
                    } else if (pendingResult != null) {
                        result.error("busy", "El probador 3D ya está abierto", null)
                    } else {
                        pendingResult = result
                        snapLauncher.launch(
                            CameraActivity.Configuration.WithLenses(
                                lensGroupIds = arrayOf(groupId),
                                applyLensById = lensId,
                                cameraFacingBasedOnLens = true,
                            )
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
