// Probador virtual con realidad aumentada.
// Cámara en vivo → ML Kit Pose Detection (33 puntos) → filtro One Euro →
// RigFitter (malla deformable) → la prenda se dibuja sobre el cuerpo, siguiendo
// torso, brazos y piernas, al tamaño real de la talla elegida.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/sizing.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'capture_preview.dart';
import 'garment_rig.dart';
import 'one_euro.dart';
import 'rig_fitter.dart';
import 'tryon_panel.dart';

/// Solo para verificación en emulador: `--dart-define=ARFIT_TEST_IMAGE=/ruta/foto.png`
/// analiza esa foto en lugar de la cámara. En el APK normal está vacío.
const _testImagePath = String.fromEnvironment('ARFIT_TEST_IMAGE');

class TryOnScreen extends StatefulWidget {
  const TryOnScreen({super.key, required this.product, this.initialSize});
  final Product product;
  final String? initialSize;

  @override
  State<TryOnScreen> createState() => _TryOnScreenState();
}

class _TryOnScreenState extends State<TryOnScreen> with WidgetsBindingObserver {
  final _detector = PoseDetector(options: PoseDetectorOptions(mode: PoseDetectionMode.stream, model: PoseDetectionModel.base));
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  CameraLensDirection _lens = CameraLensDirection.front;
  bool _busy = false;
  String? _error;

  ui.Image? _front, _backImage, _testImage;
  RigFitter? _fitter;
  String? _size;
  BodyMeasures? _body;

  // pose actual (lienzo, suavizada) y estado de los filtros por punto
  BodyFrame? _frame;
  Size? _imageSize;
  InputImageRotation _rotation = InputImageRotation.rotation270deg;
  final _filters = <PoseLandmarkType, OneEuroFilter2D>{};
  final _lastSeen = <PoseLandmarkType, double>{};
  final _lastPos = <PoseLandmarkType, Offset>{};
  String? _hint;
  bool _showSkeleton = false;

  // captura de foto: el próximo cuadro de la cámara se copia para componer la imagen
  Completer<_RawFrame>? _frameRequest;
  bool _capturing = false;
  bool _flash = false;
  // temporizador de la foto (compartido con el probador 3D)
  final _timer = PhotoTimer();

  // ajuste manual del usuario (pellizcar / arrastrar)
  double _userScale = 1;
  Offset _userOffset = Offset.zero;
  double _gestureStartScale = 1;

  Product get p => widget.product;

  @override
  void initState() {
    super.initState();
    _timer.addListener(() => mounted ? setState(() {}) : null);
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    final state = context.read<AppState>();
    _body = state.body ??
        BodyMeasures.estimate(heightCm: 168, weightKg: 65, gender: state.profile?.gender); // respaldo sin medidas
    _size = widget.initialSize ?? recommendSize(state.body, state.profile?.size, p)?.size ?? p.sizes.firstOrNull;
    Api.track(p.id, 'tryon');
    _loadGarment();
    if (_testImagePath.isNotEmpty) {
      _initTestImage();
    } else {
      _initCamera();
    }
  }

  /// Esqueleto sintético (brazos en cruz) para verificar el render en el dispositivo.
  Future<void> _initSyntheticTest() async {
    const scale = 3.0, hip = Offset(240, 360);
    const cm = <PoseLandmarkType, Offset>{
      PoseLandmarkType.nose: Offset(0, -71),
      PoseLandmarkType.leftEye: Offset(-3, -74),
      PoseLandmarkType.rightEye: Offset(3, -74),
      PoseLandmarkType.leftShoulder: Offset(-20, -51),
      PoseLandmarkType.rightShoulder: Offset(20, -51),
      PoseLandmarkType.leftElbow: Offset(-48, -56),
      PoseLandmarkType.rightElbow: Offset(46, -40),
      PoseLandmarkType.leftWrist: Offset(-74, -62),
      PoseLandmarkType.rightWrist: Offset(56, -14),
      PoseLandmarkType.leftHip: Offset(-9, 0),
      PoseLandmarkType.rightHip: Offset(9, 0),
      PoseLandmarkType.leftKnee: Offset(-14, 41),
      PoseLandmarkType.rightKnee: Offset(10, 42),
      PoseLandmarkType.leftAnkle: Offset(-20, 80),
      PoseLandmarkType.rightAnkle: Offset(12, 82),
    };
    final pts = cm.map((k, v) => MapEntry(k, hip + v * scale));
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(const Rect.fromLTWH(0, 0, 480, 640), Paint()..color = const Color(0xFF39404A));
    final bone = Paint()
      ..color = const Color(0xFFD9A47E)
      ..strokeWidth = 26
      ..strokeCap = StrokeCap.round;
    for (final (a, b) in const [
      (PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder),
      (PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow),
      (PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist),
      (PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow),
      (PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist),
      (PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip),
      (PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip),
      (PoseLandmarkType.leftHip, PoseLandmarkType.rightHip),
      (PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee),
      (PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle),
      (PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee),
      (PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle),
    ]) {
      c.drawLine(pts[a]!, pts[b]!, bone);
    }
    c.drawCircle(pts[PoseLandmarkType.nose]!, 30, bone);
    final img = await rec.endRecording().toImage(480, 640);
    if (!mounted) return;
    setState(() {
      _testImage = img;
      _frame = BodyFrame(pts, {for (final k in pts.keys) k: 0.95});
    });
  }

  Future<void> _initTestImage() async {
    if (_testImagePath == 'synthetic') return _initSyntheticTest();
    try {
      final codec = await ui.instantiateImageCodec(await File(_testImagePath).readAsBytes());
      final img = (await codec.getNextFrame()).image;
      final poses = await _detector.processImage(InputImage.fromFilePath(_testImagePath));
      if (!mounted) return;
      setState(() {
        _testImage = img;
        if (poses.isEmpty) {
          _hint = 'Sin persona detectada en la foto de prueba';
        } else {
          final pts = <PoseLandmarkType, Offset>{};
          final conf = <PoseLandmarkType, double>{};
          poses.first.landmarks.forEach((t, lm) {
            pts[t] = Offset(lm.x, lm.y);
            conf[t] = lm.likelihood;
          });
          _frame = BodyFrame(pts, conf);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Foto de prueba: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _stopCamera();
    } else if (state == AppLifecycleState.resumed) {
      _startCamera();
    }
  }

  // ------------------------------------------------------------------ prenda
  static Future<ui.Image> _loadImage(String url) async {
    final bytes = await NetworkAssetBundle(Uri.parse(url)).load(url);
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  }

  Future<void> _loadGarment() async {
    try {
      final front = await _loadImage(p.arImage);
      ui.Image? back;
      if (p.tryonBackUrl != null) {
        back = await _loadImage(p.tryonBackUrl!).catchError((Object _) => front);
      }
      final imageSize = Size(front.width.toDouble(), front.height.toDouble());
      final rig = GarmentRig.fromJson(p.tryonRig, imageSize) ??
          GarmentRig.fallback(
            opaque: await _opaqueBounds(front),
            tryonType: p.tryonType,
            anchor: p.tryonAnchor,
            image: imageSize,
          );
      if (!mounted) return;
      setState(() {
        _front = front;
        _backImage = back;
        _fitter = RigFitter(rig, _body!);
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo cargar la prenda: $e');
    }
  }

  /// Rectángulo de píxeles opacos de la imagen (para PNG sin recortar).
  static Future<Rect> _opaqueBounds(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final w = image.width, h = image.height;
    var minX = w, minY = h, maxX = 0, maxY = 0;
    final bytes = data.buffer.asUint8List();
    for (var y = 0; y < h; y += 2) {
      for (var x = 0; x < w; x += 2) {
        if (bytes[(y * w + x) * 4 + 3] > 40) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (maxX <= minX) return Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    return Rect.fromLTRB(minX.toDouble(), minY.toDouble(), maxX.toDouble() + 1, maxY.toDouble() + 1);
  }

  // ------------------------------------------------------------------ cámara
  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      await _startCamera();
    } on CameraException catch (e) {
      setState(() => _error = e.code == 'CameraAccessDenied'
          ? 'Necesitamos permiso de cámara para el probador virtual'
          : 'Error de cámara: ${e.description}');
    }
  }

  Future<void> _startCamera() async {
    if (_cameras.isEmpty) {
      setState(() => _error = 'No se encontró ninguna cámara');
      return;
    }
    final camera = _cameras.firstWhere((c) => c.lensDirection == _lens, orElse: () => _cameras.first);
    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    _controller = controller;
    try {
      await controller.initialize();
      await controller.startImageStream((img) {
        _grabFrame(img);
        _process(img, camera);
      });
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _error = e.code.contains('Denied')
            ? 'Necesitamos permiso de cámara para el probador virtual'
            : 'Error de cámara: ${e.description}');
      }
      return;
    }
    if (mounted) setState(() {});
  }

  Future<void> _stopCamera() async {
    final c = _controller;
    _controller = null;
    if (c == null) return;
    if (c.value.isStreamingImages) await c.stopImageStream();
    await c.dispose();
  }

  Future<void> _switchCamera() async {
    await _stopCamera();
    setState(() {
      _lens = _lens == CameraLensDirection.front ? CameraLensDirection.back : CameraLensDirection.front;
      _frame = null;
      _filters.clear();
      _lastSeen.clear();
      _lastPos.clear();
      if (_fitter != null) _fitter = RigFitter(_fitter!.rig, _body!);
    });
    await _startCamera();
  }

  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  InputImage? _toInputImage(CameraImage image, CameraDescription camera) {
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    } else {
      var comp = _orientations[_controller?.value.deviceOrientation ?? DeviceOrientation.portraitUp] ?? 0;
      comp = camera.lensDirection == CameraLensDirection.front
          ? (camera.sensorOrientation + comp) % 360
          : (camera.sensorOrientation - comp + 360) % 360;
      rotation = InputImageRotationValue.fromRawValue(comp);
    }
    if (rotation == null) return null;
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;
    _rotation = rotation;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  // ------------------------------------------------------------ captura
  void _grabFrame(CameraImage image) {
    final req = _frameRequest;
    if (req == null || req.isCompleted || image.planes.isEmpty) return;
    final plane = image.planes.first;
    req.complete(_RawFrame(
      Uint8List.fromList(plane.bytes),
      image.width,
      image.height,
      plane.bytesPerRow,
      _rotation.rawValue,
    ));
  }

  /// Foto = cuadro de la cámara (enderezado igual que los puntos de ML Kit)
  /// + la prenda dibujada encima con la misma malla que se ve en pantalla.
  Future<void> _capture() async {
    if (_capturing) return;
    final outcome = _fit();
    final garment = outcome != null && outcome.back && _backImage != null ? _backImage : _front;
    if (outcome?.mesh == null || garment == null) {
      showInfo(context, 'Colócate frente a la cámara hasta que la prenda aparezca sobre ti');
      return;
    }
    setState(() {
      _capturing = true;
      _flash = true;
    });
    Future.delayed(const Duration(milliseconds: 160), () => mounted ? setState(() => _flash = false) : null);
    try {
      ui.Image base;
      Size canvasSize;
      if (_testImage != null) {
        base = _testImage!;
        canvasSize = Size(base.width.toDouble(), base.height.toDouble());
      } else {
        final preview = _controller?.value.previewSize;
        if (preview == null || !Platform.isAndroid) throw Exception('Cámara no disponible');
        canvasSize = Size(preview.height, preview.width);
        _frameRequest = Completer<_RawFrame>();
        final raw = await _frameRequest!.future.timeout(const Duration(seconds: 2));
        final mirror = _lens == CameraLensDirection.front;
        final rgba = await compute(_nv21ToUprightRgba, (frame: raw, mirror: mirror));
        base = await _decodeRgba(rgba.pixels, rgba.width, rgba.height);
      }
      final bytes = await _compose(base, canvasSize, outcome!.mesh!, garment);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => CapturePreview.bytes(bytes, title: p.name)));
    } catch (e) {
      if (mounted) showError(context, 'No se pudo tomar la foto: $e');
    } finally {
      _frameRequest = null;
      if (mounted) setState(() => _capturing = false);
    }
  }

  static Future<ui.Image> _decodeRgba(Uint8List px, int w, int h) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }

  Future<Uint8List> _compose(ui.Image base, Size canvasSize, GarmentMesh mesh, ui.Image garment) async {
    // la cámara entrega ~720×480: se dibuja al doble para que la prenda salga nítida
    final k = _testImage != null ? 1.0 : 2.0;
    final out = Size(canvasSize.width * k, canvasSize.height * k);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & out);
    canvas.scale(k);
    canvas.drawImageRect(
      base,
      Rect.fromLTWH(0, 0, base.width.toDouble(), base.height.toDouble()),
      Offset.zero & canvasSize,
      Paint()..filterQuality = FilterQuality.medium,
    );
    _GarmentPainter(image: garment, mesh: mesh, userScale: _userScale, userOffset: _userOffset).paint(canvas, canvasSize);
    // sello con la prenda y la talla
    final label = TextPainter(
      text: TextSpan(
        text: 'AR-FIT · ${p.name}${_size != null ? ' · talla $_size' : ''}',
        style: TextStyle(color: Colors.white, fontSize: canvasSize.width * 0.035, fontWeight: FontWeight.w700, shadows: const [Shadow(blurRadius: 6)]),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: canvasSize.width * 0.92);
    label.paint(canvas, Offset(canvasSize.width * 0.04, canvasSize.height - label.height - canvasSize.width * 0.04));
    final img = await recorder.endRecording().toImage(out.width.round(), out.height.round());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  Future<void> _process(CameraImage image, CameraDescription camera) async {
    if (_busy) return;
    _busy = true;
    try {
      final input = _toInputImage(image, camera);
      if (input == null) return;
      final poses = await _detector.processImage(input);
      if (!mounted) return;
      final preview = _controller?.value.previewSize;
      if (preview == null) return;
      _imageSize = input.metadata!.size;
      setState(() {
        if (poses.isEmpty) {
          _frame = null;
          _hint = 'Aléjate ~2 m y colócate frente a la cámara';
        } else {
          _frame = _smoothFrame(poses.first, Size(preview.height, preview.width));
        }
      });
    } catch (e) {
      debugPrint('pose: $e');
    } finally {
      _busy = false;
    }
  }

  // ----------------------------------------------------- coordenadas → lienzo
  Offset _toCanvas(double x, double y, Size canvas) {
    final img = _imageSize!;
    final rotated = _rotation == InputImageRotation.rotation90deg || _rotation == InputImageRotation.rotation270deg;
    final iw = Platform.isAndroid && rotated ? img.height : img.width;
    final ih = Platform.isAndroid && rotated ? img.width : img.height;
    var cx = x * canvas.width / iw;
    final cy = y * canvas.height / ih;
    // la cámara frontal se muestra en espejo
    final mirror = _lens == CameraLensDirection.front;
    if (_rotation == InputImageRotation.rotation270deg || (!rotated && mirror)) cx = canvas.width - cx;
    return Offset(cx, cy);
  }

  /// Convierte la pose al lienzo y suaviza cada punto con un filtro One Euro.
  /// Si un punto se pierde un instante (oclusión, desenfoque) se conserva su
  /// última posición durante 0,4 s para que la manga no "salte".
  BodyFrame _smoothFrame(Pose pose, Size canvas) {
    final now = DateTime.now().microsecondsSinceEpoch / 1e6;
    final pts = <PoseLandmarkType, Offset>{};
    final conf = <PoseLandmarkType, double>{};
    pose.landmarks.forEach((type, lm) {
      final raw = _toCanvas(lm.x, lm.y, canvas);
      if (lm.likelihood >= 0.5) {
        final p = _filters.putIfAbsent(type, OneEuroFilter2D.new).filter(raw, now);
        _lastSeen[type] = now;
        _lastPos[type] = p;
        pts[type] = p;
        conf[type] = lm.likelihood;
      } else if (_lastPos[type] != null && now - (_lastSeen[type] ?? 0) < 0.4) {
        pts[type] = _lastPos[type]!;
        conf[type] = 0.5;
      } else {
        pts[type] = raw;
        conf[type] = lm.likelihood;
      }
    });
    return BodyFrame(pts, conf);
  }

  FitOutcome? _fit() {
    final frame = _frame, fitter = _fitter;
    if (frame == null || fitter == null || _size == null) return null;
    final mirrored = _testImage == null && _lens == CameraLensDirection.front;
    var outcome = fitter.fit(frame, p.sizeChart[_size] ?? const SizeMeasures(), mirrored: mirrored);
    if (_testImage != null) {
      // foto fija: se repite para estabilizar la detección frente/espalda
      for (var i = 0; i < 15; i++) {
        outcome = fitter.fit(frame, p.sizeChart[_size] ?? const SizeMeasures(), mirrored: false);
      }
    }
    _hint = outcome.hint;
    return outcome;
  }

  @override
  void dispose() {
    _timer.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _stopCamera();
    _detector.close();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  // ----------------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        if (_error != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            ),
          )
        else if (_testImage != null)
          Positioned.fill(child: _testImageWithOverlay(_testImage!))
        else if (!ready)
          const Center(child: CircularProgressIndicator(color: Colors.white))
        else
          Positioned.fill(child: _cameraWithOverlay(controller)),
        _topBar(),
        if (_error == null && _front == null)
          Positioned(
            top: MediaQuery.of(context).padding.top + 64,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(20)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  SizedBox(width: 10),
                  Text('Cargando prenda…', style: TextStyle(color: Colors.white)),
                ]),
              ),
            ),
          )
        else if ((ready || _testImage != null) && _hint != null && _error == null)
          Positioned(
            top: MediaQuery.of(context).padding.top + 64,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                const Icon(Icons.accessibility_new, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(_hint!, style: const TextStyle(color: Colors.white))),
              ]),
            ),
          ),
        Positioned(left: 0, right: 0, bottom: 0, child: _bottomPanel()),
        CountdownOverlay(timer: _timer),
        FlashOverlay(visible: _flash),
      ]),
    );
  }

  Widget _testImageWithOverlay(ui.Image img) {
    final outcome = _fit();
    final garment = outcome != null && outcome.back && _backImage != null ? _backImage : _front;
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: img.width.toDouble(),
        height: img.height.toDouble(),
        child: Stack(fit: StackFit.expand, children: [
          RawImage(image: img),
          CustomPaint(
            painter: _GarmentPainter(
              image: garment,
              mesh: outcome?.mesh,
              userScale: _userScale,
              userOffset: _userOffset,
              skeleton: _showSkeleton ? _frame?.pts : null,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _cameraWithOverlay(CameraController controller) {
    final preview = controller.value.previewSize!;
    // en vertical la vista previa está rotada: ancho = alto del sensor
    final canvasSize = Size(preview.height, preview.width);
    final outcome = _fit();
    final image = outcome != null && outcome.back && _backImage != null ? _backImage : _front;
    return LayoutBuilder(builder: (context, constraints) {
      final scale = math.max(constraints.maxWidth / canvasSize.width, constraints.maxHeight / canvasSize.height);
      return GestureDetector(
        onScaleStart: (_) => _gestureStartScale = _userScale,
        onScaleUpdate: (d) => setState(() {
          _userScale = (_gestureStartScale * d.scale).clamp(0.6, 1.8);
          _userOffset += d.focalPointDelta / scale;
        }),
        onDoubleTap: () => setState(() {
          _userScale = 1;
          _userOffset = Offset.zero;
        }),
        child: ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: canvasSize.width,
              height: canvasSize.height,
              child: Stack(fit: StackFit.expand, children: [
                CameraPreview(controller),
                CustomPaint(
                  painter: _GarmentPainter(
                    image: image,
                    mesh: outcome?.mesh,
                    userScale: _userScale,
                    userOffset: _userOffset,
                    skeleton: _showSkeleton ? _frame?.pts : null,
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    });
  }

  Widget _topBar() => TryOnTopBar(
        title: p.name,
        subtitle: 'Probador virtual · RA',
        actions: [
          tryOnRoundButton(_showSkeleton ? Icons.person : Icons.person_outline, () => setState(() => _showSkeleton = !_showSkeleton),
              tooltip: 'Ver puntos detectados por IA'),
          tryOnRoundButton(Icons.cameraswitch_outlined, _switchCamera, tooltip: 'Cambiar cámara'),
        ],
      );



  Widget _bottomPanel() {
    final body = _body!;
    return TryOnBottomPanel(
      product: p,
      body: body,
      size: _size,
      onSize: (s) => setState(() => _size = s),
      timer: _timer,
      capturing: _capturing,
      onShoot: _capture,
      showShutter: _error == null && (_controller?.value.isInitialized == true || _testImage != null),
      footnote: body.estimated
          ? 'Medidas estimadas por altura y peso · pellizca para ajustar, doble toque para reiniciar'
          : 'Ajustado a tus medidas · pellizca para ajustar, doble toque para reiniciar',
    );
  }

}

class _GarmentPainter extends CustomPainter {
  _GarmentPainter({
    required this.image,
    required this.mesh,
    required this.userScale,
    required this.userOffset,
    this.skeleton,
  });

  final ui.Image? image;
  final GarmentMesh? mesh;
  final double userScale;
  final Offset userOffset;
  final Map<PoseLandmarkType, Offset>? skeleton;

  static final _identity = Float64List.fromList([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

  static const _bones = [
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
    [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
    [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
    [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
    [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
    [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final m = mesh, img = image;
    if (m != null && img != null) {
      canvas.save();
      // ajuste manual: desplazamiento + escala alrededor del centro del cuerpo
      canvas.translate(m.pivot.dx + userOffset.dx, m.pivot.dy + userOffset.dy);
      canvas.scale(userScale);
      canvas.translate(-m.pivot.dx, -m.pivot.dy);
      final paint = Paint()
        ..shader = ui.ImageShader(img, TileMode.clamp, TileMode.clamp, _identity, filterQuality: FilterQuality.medium);
      final vertices = m.toVertices();
      canvas.drawVertices(vertices, BlendMode.srcOver, paint);
      vertices.dispose();
      canvas.restore();
    }
    final sk = skeleton;
    if (sk != null) {
      final line = Paint()
        ..color = AppColors.ai
        ..strokeWidth = 3;
      for (final b in _bones) {
        final a = sk[b[0]], c = sk[b[1]];
        if (a != null && c != null) canvas.drawLine(a, c, line);
      }
      final dot = Paint()..color = Colors.white;
      for (final o in sk.values) {
        canvas.drawCircle(o, 3.5, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GarmentPainter old) => true;
}

/// Copia de un cuadro NV21 de la cámara.
class _RawFrame {
  const _RawFrame(this.bytes, this.width, this.height, this.stride, this.rotation);
  final Uint8List bytes;
  final int width, height, stride, rotation;
}

/// NV21 → RGBA enderezado con la misma rotación y espejo que se aplica a los
/// puntos de ML Kit (ver _toCanvas), para que la prenda calce sobre la foto.
({Uint8List pixels, int width, int height}) _nv21ToUprightRgba(({_RawFrame frame, bool mirror}) a) {
  final f = a.frame, w = f.width, h = f.height, st = f.stride, src = f.bytes;
  final rotated = f.rotation == 90 || f.rotation == 270;
  final ow = rotated ? h : w, oh = rotated ? w : h;
  final flip = f.rotation == 270 || (!rotated && a.mirror);
  final out = Uint8List(ow * oh * 4);
  final uvBase = st * h;
  for (var y = 0; y < h; y++) {
    final uvRow = uvBase + (y >> 1) * st;
    for (var x = 0; x < w; x++) {
      final yy = src[y * st + x];
      final uvi = uvRow + (x & ~1);
      final v = src[uvi] - 128, u = src[uvi + 1] - 128;
      var r = (yy + 1.402 * v).round(), g = (yy - 0.344136 * u - 0.714136 * v).round(), b = (yy + 1.772 * u).round();
      r = r < 0 ? 0 : (r > 255 ? 255 : r);
      g = g < 0 ? 0 : (g > 255 ? 255 : g);
      b = b < 0 ? 0 : (b > 255 ? 255 : b);
      int ox, oy;
      switch (f.rotation) {
        case 90:
          ox = h - 1 - y;
          oy = x;
        case 270:
          ox = y;
          oy = w - 1 - x;
        case 180:
          ox = w - 1 - x;
          oy = h - 1 - y;
        default:
          ox = x;
          oy = y;
      }
      if (flip) ox = ow - 1 - ox;
      final o = (oy * ow + ox) * 4;
      out[o] = r;
      out[o + 1] = g;
      out[o + 2] = b;
      out[o + 3] = 255;
    }
  }
  return (pixels: out, width: ow, height: oh);
}
