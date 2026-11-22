package pe.arfit.arfit

import android.content.Context
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.view.View
import com.snap.camerakit.Session
import com.snap.camerakit.lenses.LensesComponent
import com.snap.camerakit.support.widget.CameraLayout
import com.snap.camerakit.support.widget.SnapButtonView
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.Closeable
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/**
 * Cámara de Snap Camera Kit incrustada en la pantalla de Flutter (vista nativa
 * "pe.arfit/snap_camera"). Muestra SOLO el lente de la prenda elegida, sin el
 * carrusel ni los botones de Snap: la interfaz (barra superior, temporizador,
 * disparador, tallas y carrito) es la misma del probador 2D, dibujada en Flutter.
 *
 * Canal por vista "pe.arfit/snap_camera_<id>":
 *   capture → ruta del JPG tomado · flip → cambia de cámara
 *   eventos hacia Flutter: lensReady(bool), error(String)
 */
class SnapCameraFactory(
    private val activity: FlutterFragmentActivity,
    private val messenger: BinaryMessenger,
    private val lensGroupId: () -> String?,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?> ?: emptyMap()
        return SnapCameraView(activity, messenger, viewId, params["lensId"] as? String ?: "", lensGroupId() ?: "")
    }
}

class SnapCameraView(
    private val activity: FlutterFragmentActivity,
    messenger: BinaryMessenger,
    viewId: Int,
    private val lensId: String,
    private val groupId: String,
) : PlatformView {

    // El contexto debe ser la actividad: CameraLayout pide permisos y se ata a su ciclo de vida
    private val layout = CameraLayout(activity)
    private val channel = MethodChannel(messenger, "pe.arfit/snap_camera_$viewId")
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private var lensObserver: Closeable? = null
    private var pendingCapture: MethodChannel.Result? = null
    private var started = false

    init {
        // Solo la vista de la cámara: los controles los dibuja Flutter
        listOf(
            layout.captureButton,
            layout.flipFacingButton,
            layout.toggleFlashButton,
            layout.toneToggleLayout,
            layout.portraitToggleLayout,
            layout.lensButton,
        ).forEach { it.visibility = View.GONE }

        // sin ajustes de tono/retrato de Snap: sus botones reaparecerían tras cada foto
        layout.enabledAdjustments = emptySet()
        layout.configureLensesCarousel { enabled = false }
        layout.onSessionAvailable { session -> applyLens(session) }
        layout.onImageTaken { bitmap -> saveCapture(bitmap) }
        layout.onError { e ->
            main.post {
                pendingCapture?.error("capture", e.message, null)
                pendingCapture = null
                channel.invokeMethod("error", e.message ?: e.toString())
            }
        }

        layout.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(v: View) {
                if (started) return
                started = true
                layout.startPreview(true) // cámara frontal, como el probador 2D
            }

            override fun onViewDetachedFromWindow(v: View) = Unit
        })

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "capture" -> {
                    if (pendingCapture != null) {
                        result.error("busy", "Ya se está tomando una foto", null)
                    } else {
                        pendingCapture = result
                        // Igual que un toque corto en el botón de Snap
                        val listener = layout.captureButton.onCaptureRequestListener
                        if (listener == null) {
                            pendingCapture = null
                            result.error("not_ready", "La cámara aún no está lista", null)
                        } else {
                            listener.onStart(SnapButtonView.CaptureType.SNAPSHOT)
                            listener.onEnd(SnapButtonView.CaptureType.SNAPSHOT)
                        }
                    }
                }
                "flip" -> {
                    layout.flipFacing()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Aplica únicamente el lente de la prenda elegida. */
    private fun applyLens(session: Session) {
        lensObserver?.close()
        lensObserver = session.lenses.repository.observe(
            LensesComponent.Repository.QueryCriteria.ById(lensId, groupId)
        ) { result ->
            val lens = (result as? LensesComponent.Repository.Result.Some)?.lenses?.firstOrNull()
            if (lens == null) {
                main.post { channel.invokeMethod("error", "No se encontró el lente 3D de esta prenda") }
            } else {
                session.lenses.processor.apply(lens) { ok -> main.post { channel.invokeMethod("lensReady", ok) } }
            }
        }
    }

    private fun saveCapture(bitmap: Bitmap) {
        io.execute {
            val reply = runCatching {
                val file = File(activity.cacheDir, "arfit_3d_${System.currentTimeMillis()}.jpg")
                FileOutputStream(file).use { bitmap.compress(Bitmap.CompressFormat.JPEG, 92, it) }
                file.absolutePath
            }
            main.post {
                val pending = pendingCapture ?: return@post
                pendingCapture = null
                reply.fold({ pending.success(it) }, { pending.error("save", it.message, null) })
            }
        }
    }

    override fun getView(): View = layout

    override fun dispose() {
        channel.setMethodCallHandler(null)
        lensObserver?.close()
        lensObserver = null
        io.shutdown()
    }
}
