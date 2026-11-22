// Probador 3D con Snap Camera Kit (ver MainActivity.kt y SnapCameraView.kt).
import 'package:flutter/services.dart';

class SnapTryOn {
  static const _channel = MethodChannel('pe.arfit/snap_tryon');
  static bool? _available;

  /// Tipo de la vista nativa con la cámara de Snap.
  static const viewType = 'pe.arfit/snap_camera';

  /// true si la app se compiló con el token y el grupo de lentes de Camera Kit.
  static Future<bool> isAvailable() async {
    if (_available != null) return _available!;
    try {
      _available = await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } catch (_) {
      _available = false;
    }
    return _available!;
  }
}
