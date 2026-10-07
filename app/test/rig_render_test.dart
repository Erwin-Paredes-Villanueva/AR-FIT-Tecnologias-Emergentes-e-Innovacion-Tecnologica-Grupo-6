// Renderiza las prendas del catálogo demo sobre esqueletos sintéticos en
// distintas poses para revisar visualmente la deformación del probador RA.
//   RIG_OUT=/ruta/salida flutter test test/rig_render_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:arfit/core/models.dart';
import 'package:arfit/core/sizing.dart';
import 'package:arfit/features/tryon/garment_rig.dart';
import 'package:arfit/features/tryon/rig_fitter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

typedef L = PoseLandmarkType;

const _scale = 3.2; // px por cm
const _hip = Offset(240, 330);
const cell = Size(480, 640);

/// Esqueleto base de frente (cm, origen en el centro de la cadera, y hacia abajo).
/// Cámara frontal en espejo: la izquierda anatómica aparece a la izquierda.
Map<L, Offset> _base() => {
      L.nose: const Offset(0, -71),
      L.leftEye: const Offset(-3, -74),
      L.rightEye: const Offset(3, -74),
      L.leftShoulder: const Offset(-20, -51),
      L.rightShoulder: const Offset(20, -51),
      L.leftElbow: const Offset(-25, -22),
      L.rightElbow: const Offset(25, -22),
      L.leftWrist: const Offset(-28, 3),
      L.rightWrist: const Offset(28, 3),
      L.leftHip: const Offset(-9, 0),
      L.rightHip: const Offset(9, 0),
      L.leftKnee: const Offset(-10, 42),
      L.rightKnee: const Offset(10, 42),
      L.leftAnkle: const Offset(-10, 82),
      L.rightAnkle: const Offset(10, 82),
    };

Map<L, Offset> _with(Map<L, Offset> m, Map<L, Offset> changes) => {...m, ...changes};

Map<L, Offset> _rotate(Map<L, Offset> m, double deg) {
  final a = deg * math.pi / 180;
  return m.map((k, v) => MapEntry(k, Offset(v.dx * math.cos(a) - v.dy * math.sin(a), v.dx * math.sin(a) + v.dy * math.cos(a))));
}

final poses = <String, (Map<L, Offset>, bool back)>{
  'frente': (_base(), false),
  'brazos en cruz': (
    _with(_base(), {
      L.leftElbow: const Offset(-50, -53),
      L.rightElbow: const Offset(50, -53),
      L.leftWrist: const Offset(-77, -54),
      L.rightWrist: const Offset(77, -54),
    }),
    false
  ),
  'brazos arriba': (
    _with(_base(), {
      L.leftElbow: const Offset(-27, -80),
      L.rightElbow: const Offset(27, -80),
      L.leftWrist: const Offset(-24, -106),
      L.rightWrist: const Offset(24, -106),
    }),
    false
  ),
  'mano en cintura': (_with(_base(), {L.leftElbow: const Offset(-42, -28), L.leftWrist: const Offset(-14, -4)}), false),
  'inclinado': (_rotate(_base(), 10), false),
  'tres cuartos': (_base().map((k, v) => MapEntry(k, Offset(v.dx * 0.55 + (k.name.contains('right') ? 4 : 0), v.dy))), false),
  'caminando': (
    _with(_base(), {
      L.leftKnee: const Offset(-17, 40),
      L.leftAnkle: const Offset(-26, 78),
      L.rightKnee: const Offset(8, 42),
      L.rightAnkle: const Offset(15, 81),
      L.leftElbow: const Offset(-20, -23),
      L.leftWrist: const Offset(-8, 0),
      L.rightElbow: const Offset(30, -24),
      L.rightWrist: const Offset(40, -2),
    }),
    false
  ),
  // de espaldas: la izquierda anatómica queda a la derecha y no se ve la cara
  'de espaldas': (
    _base().map((k, v) => MapEntry(k, Offset(-v.dx, v.dy))),
    true
  ),
};

BodyFrame _frame(Map<L, Offset> cm, bool back) => BodyFrame(
      cm.map((k, v) => MapEntry(k, _hip + v * _scale)),
      {for (final k in cm.keys) k: (back && (k == L.nose || k.name.contains('Eye'))) ? 0.05 : 0.95},
    );

void _drawBody(Canvas c, Map<L, Offset> cm) {
  Offset p(L t) => _hip + cm[t]! * _scale;
  final skin = Paint()
    ..color = const Color(0xFFD9A47E)
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  void limb(L a, L b, double w) => c.drawLine(p(a), p(b), skin..strokeWidth = w * _scale);
  limb(L.leftHip, L.leftKnee, 15);
  limb(L.leftKnee, L.leftAnkle, 11);
  limb(L.rightHip, L.rightKnee, 15);
  limb(L.rightKnee, L.rightAnkle, 11);
  final torso = Path()
    ..moveTo(p(L.leftShoulder).dx, p(L.leftShoulder).dy)
    ..lineTo(p(L.rightShoulder).dx, p(L.rightShoulder).dy)
    ..lineTo(p(L.rightHip).dx + 4 * _scale, p(L.rightHip).dy)
    ..lineTo(p(L.leftHip).dx - 4 * _scale, p(L.leftHip).dy)
    ..close();
  c.drawPath(torso, Paint()..color = const Color(0xFFD9A47E));
  c.drawPath(torso, skin..strokeWidth = 8 * _scale);
  limb(L.leftShoulder, L.leftElbow, 10);
  limb(L.leftElbow, L.leftWrist, 8);
  limb(L.rightShoulder, L.rightElbow, 10);
  limb(L.rightElbow, L.rightWrist, 8);
  final head = (p(L.nose) + Offset(0, -2 * _scale));
  c.drawCircle(head, 11 * _scale, Paint()..color = const Color(0xFFD9A47E));
}

Future<ui.Image> _decode(String path) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  return (await codec.getNextFrame()).image;
}

void main() {
  final out = Platform.environment['RIG_OUT'];

  testWidgets('render de prendas deformadas', (tester) async {
    await tester.runAsync(() async {
      final dir = '../tools/seed/images';
      final anchors = jsonDecode(File('$dir/anchors.json').readAsStringSync()) as Map<String, dynamic>;
      final male = BodyMeasures.estimate(heightCm: 170, weightKg: 68, gender: 'hombre');
      final female = BodyMeasures.estimate(heightCm: 165, weightKg: 58, gender: 'mujer');
      final garments = <(String, SizeMeasures, BodyMeasures)>[
        ('polo-mostaza', const SizeMeasures(chest: 102, length: 70), male),
        ('camisa-cuadros', const SizeMeasures(chest: 106, length: 74), male),
        ('polera-gris', const SizeMeasures(chest: 110, length: 68), male),
        ('vestido-rojo', const SizeMeasures(chest: 90, waist: 72, hip: 98, length: 99), female),
        ('pantalon-jean', const SizeMeasures(waist: 80, hip: 102, length: 102), male),
        ('falda-plisada', const SizeMeasures(waist: 72, hip: 100, length: 47), female),
      ];
      const thumb = 0.5;
      final cols = poses.length;
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      final total = Size(cell.width * thumb * cols, cell.height * thumb * garments.length + 30);
      canvas.drawRect(Offset.zero & total, Paint()..color = const Color(0xFFF2EFEA));

      for (var g = 0; g < garments.length; g++) {
        final (name, size, body) = garments[g];
        final front = await _decode('$dir/$name.png');
        final back = await _decode('$dir/$name-back.png');
        final rig = GarmentRig.fromJson(
          (anchors[name] as Map<String, dynamic>)['rig'] as Map<String, dynamic>,
          Size(front.width.toDouble(), front.height.toDouble()),
        )!;
        var col = 0;
        for (final entry in poses.entries) {
          final (cm, isBack) = entry.value;
          final fitter = RigFitter(rig, body);
          FitOutcome? outcome;
          for (var i = 0; i < 15; i++) {
            outcome = fitter.fit(_frame(cm, isBack), size, mirrored: true);
          }
          canvas.save();
          canvas.translate(col * cell.width * thumb, g * cell.height * thumb);
          canvas.scale(thumb);
          canvas.clipRect(Offset.zero & cell);
          _drawBody(canvas, cm);
          final mesh = outcome!.mesh;
          expect(mesh, isNotNull, reason: '$name / ${entry.key}: ${outcome.hint}');
          expect(outcome.back, isBack, reason: '$name / ${entry.key}: detección frente/espalda');
          final img = outcome.back ? back : front;
          final paint = Paint()
            ..shader = ui.ImageShader(img, TileMode.clamp, TileMode.clamp,
                Float64List.fromList([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
                filterQuality: FilterQuality.medium);
          canvas.drawVertices(mesh!.toVertices(), BlendMode.srcOver, paint);
          canvas.restore();
          col++;
        }
      }
      if (out != null) {
        final image = await rec.endRecording().toImage(total.width.toInt(), total.height.toInt());
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$out/rig_poses.png').writeAsBytesSync(png!.buffer.asUint8List());
      }
    });
  });
}
