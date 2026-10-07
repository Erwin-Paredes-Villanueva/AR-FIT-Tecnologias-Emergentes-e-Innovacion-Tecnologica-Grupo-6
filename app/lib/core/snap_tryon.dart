// Puente con el probador 3D nativo (Snap Camera Kit, ver MainActivity.kt).
import 'package:flutter/services.dart';

class SnapTryOnResult {
  const SnapTryOnResult(this.status, {this.uri, this.error});
  final String status; // image | video | cancelled | failure
  final String? uri;
  final String? error;
}

class SnapTryOn {
  static const _channel = MethodChannel('pe.arfit/snap_tryon');
  static bool? _available;

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

  static Future<SnapTryOnResult> launch(String lensId) async {
    try {
      final r = await _channel.invokeMapMethod<String, dynamic>('launch', {'lensId': lensId});
      return SnapTryOnResult(r?['status'] as String? ?? 'cancelled', uri: r?['uri'] as String?, error: r?['error'] as String?);
    } on PlatformException catch (e) {
      return SnapTryOnResult('failure', error: e.message);
    }
  }
}
