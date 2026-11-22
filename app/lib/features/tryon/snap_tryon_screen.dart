import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/sizing.dart';
import '../../core/snap_tryon.dart';
import '../../widgets/common.dart';
import 'capture_preview.dart';
import 'tryon_panel.dart';

/// Probador 3D: la cámara de Snap Camera Kit con el lente de ESTA prenda
/// (seguimiento corporal 3D y simulación de tela), con la misma interfaz que
/// el probador 2D: barra superior, temporizador, disparador, tallas y carrito.
/// Devuelve la talla elegida, igual que el probador 2D.
class SnapTryOnScreen extends StatefulWidget {
  const SnapTryOnScreen({super.key, required this.product, this.initialSize});
  final Product product;
  final String? initialSize;

  @override
  State<SnapTryOnScreen> createState() => _SnapTryOnScreenState();
}

class _SnapTryOnScreenState extends State<SnapTryOnScreen> {
  final _timer = PhotoTimer();
  MethodChannel? _channel;
  late BodyMeasures _body;
  String? _size;
  bool _lensReady = false;
  bool _capturing = false;
  bool _flash = false;
  String? _error;

  Product get p => widget.product;

  @override
  void initState() {
    super.initState();
    _timer.addListener(() => mounted ? setState(() {}) : null);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    final state = context.read<AppState>();
    _body = state.body ?? BodyMeasures.estimate(heightCm: 168, weightKg: 65, gender: state.profile?.gender);
    _size = widget.initialSize ?? recommendSize(state.body, state.profile?.size, p)?.size ?? p.sizes.firstOrNull;
    Api.track(p.id, 'tryon');
  }

  void _onViewCreated(int id) {
    final channel = MethodChannel('pe.arfit/snap_camera_$id');
    channel.setMethodCallHandler((call) async {
      if (!mounted) return;
      switch (call.method) {
        case 'lensReady':
          setState(() => _lensReady = call.arguments == true);
        case 'error':
          setState(() => _error = call.arguments?.toString() ?? 'Error de la cámara 3D');
      }
    });
    _channel = channel;
  }

  Future<void> _capture() async {
    final channel = _channel;
    if (channel == null || _capturing) return;
    setState(() {
      _capturing = true;
      _flash = true;
    });
    Future.delayed(const Duration(milliseconds: 160), () => mounted ? setState(() => _flash = false) : null);
    try {
      final path = await channel.invokeMethod<String>('capture');
      if (!mounted || path == null) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => CapturePreview.file(File(path), title: p.name)));
    } on PlatformException catch (e) {
      if (mounted) showError(context, e.message ?? 'No se pudo tomar la foto');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  void dispose() {
    _timer.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // Cámara de Snap como vista nativa (composición híbrida, recomendada para cámara)
        Positioned.fill(
          child: PlatformViewLink(
            viewType: SnapTryOn.viewType,
            surfaceFactory: (context, controller) => AndroidViewSurface(
              controller: controller as AndroidViewController,
              gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
              hitTestBehavior: PlatformViewHitTestBehavior.opaque,
            ),
            onCreatePlatformView: (params) {
              final controller = PlatformViewsService.initExpensiveAndroidView(
                id: params.id,
                viewType: SnapTryOn.viewType,
                layoutDirection: TextDirection.ltr,
                creationParams: {'lensId': p.tryonLensId},
                creationParamsCodec: const StandardMessageCodec(),
                onFocus: () => params.onFocusChanged(true),
              );
              controller
                ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
                ..addOnPlatformViewCreatedListener(_onViewCreated)
                ..create();
              return controller;
            },
          ),
        ),
        TryOnTopBar(
          title: p.name,
          subtitle: 'Probador 3D · RA · Powered by Snap',
          actions: [
            tryOnRoundButton(Icons.cameraswitch_outlined, () => _channel?.invokeMethod('flip'), tooltip: 'Cambiar cámara'),
          ],
        ),
        if (_error != null || !_lensReady)
          Positioned(
            top: MediaQuery.of(context).padding.top + 64,
            left: 20,
            right: 20,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (_error == null)
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  else
                    const Icon(Icons.error_outline, color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(_error ?? 'Cargando prenda 3D…', style: const TextStyle(color: Colors.white)),
                  ),
                ]),
              ),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: TryOnBottomPanel(
            product: p,
            body: _body,
            size: _size,
            onSize: (s) => setState(() => _size = s),
            timer: _timer,
            capturing: _capturing,
            onShoot: _capture,
            showShutter: _error == null,
            footnote: 'Ponte de cuerpo entero a unos 2 m: la prenda sigue tus movimientos y se adapta a tu cuerpo',
          ),
        ),
        CountdownOverlay(timer: _timer),
        FlashOverlay(visible: _flash),
      ]),
    );
  }
}
