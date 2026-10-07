// Deformación de la prenda con el esqueleto detectado.
//
// En lugar de pegar una imagen rígida, la prenda se convierte en una malla de
// triángulos texturizada:
//   · Torso: una cuadrícula que se interpola entre la línea de hombros y la de
//     caderas (se inclina, se tuerce y se angosta al girar) y, en vestidos,
//     continúa siguiendo la dirección de las piernas.
//   · Mangas y piernas: tiras que recorren hombro→codo→muñeca o
//     cadera→rodilla→tobillo, así que se doblan y levantan con el cuerpo.
// La escala sale de las medidas reales del usuario y de la talla elegida: una
// talla mayor se dibuja más ancha y más larga sobre el mismo cuerpo.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../core/models.dart';
import '../../core/sizing.dart';
import 'garment_rig.dart';

typedef _L = PoseLandmarkType;

/// Puntos del cuerpo ya convertidos a coordenadas del lienzo.
class BodyFrame {
  const BodyFrame(this.pts, this.conf);
  final Map<PoseLandmarkType, Offset> pts;
  final Map<PoseLandmarkType, double> conf;

  Offset? get(PoseLandmarkType t, [double min = 0.5]) => (conf[t] ?? 0) >= min ? pts[t] : null;
}

class GarmentMesh {
  GarmentMesh(this.positions, this.uvs, this.indices, this.pivot);
  final Float32List positions; // x,y en el lienzo
  final Float32List uvs; // x,y en píxeles de la imagen de la prenda
  final Uint16List indices;
  final Offset pivot; // centro para el ajuste manual (pellizcar)

  Vertices toVertices() =>
      Vertices.raw(VertexMode.triangles, positions, textureCoordinates: uvs, indices: indices);
}

class FitOutcome {
  const FitOutcome({this.mesh, this.hint, this.back = false});
  final GarmentMesh? mesh;
  final String? hint;
  final bool back; // la persona está de espaldas → usar la vista trasera
}

class RigFitter {
  RigFitter(this.rig, this.body);

  final GarmentRig rig;
  final BodyMeasures body;

  double? _hipRatioRef; // relación cadera/hombros habitual (para detectar torsión)
  double _backScore = 0;
  bool _back = false;

  FitOutcome fit(BodyFrame f, SizeMeasures size, {required bool mirrored}) {
    _updateFacing(f, mirrored);
    final mb = _MeshBuilder();
    final hint = rig.type == 'bottom' ? _fitBottom(f, size, mb) : _fitTop(f, size, mb);
    if (hint != null) return FitOutcome(hint: hint, back: _back);
    if (mb.isEmpty || !mb.isFinite) return FitOutcome(hint: 'Colócate de frente a la cámara', back: _back);
    return FitOutcome(mesh: mb.build(), back: _back);
  }

  // ------------------------------------------------------------ frente/espalda
  /// De espaldas: el orden izquierda/derecha de los hombros se invierte y la
  /// cara deja de verse. Se combina con histéresis para que no parpadee.
  void _updateFacing(BodyFrame f, bool mirrored) {
    final ls = f.pts[_L.leftShoulder], rs = f.pts[_L.rightShoulder];
    if (ls == null || rs == null) return;
    // con la cámara frontal (espejo) la izquierda anatómica aparece a la izquierda
    final anatomicalLeftOnLeft = ls.dx < rs.dx;
    final orderSaysBack = mirrored ? !anatomicalLeftOnLeft : anatomicalLeftOnLeft;
    final face = ((f.conf[_L.nose] ?? 0) + (f.conf[_L.leftEye] ?? 0) + (f.conf[_L.rightEye] ?? 0)) / 3;
    final faceHidden = (1 - face / 0.5).clamp(0.0, 1.0);
    final target = 0.4 * (orderSaysBack ? 1 : 0) + 0.6 * faceHidden;
    _backScore = _backScore * 0.7 + target * 0.3;
    if (!_back && _backScore > 0.5) {
      _back = true;
    } else if (_back && _backScore < 0.35) {
      _back = false;
    }
  }

  // ---------------------------------------------------------- polos/vestidos
  String? _fitTop(BodyFrame f, SizeMeasures size, _MeshBuilder mb) {
    final lsA = f.get(_L.leftShoulder), rsA = f.get(_L.rightShoulder);
    if (lsA == null || rsA == null) return 'Colócate de frente con los hombros visibles';
    // a = hombro a la izquierda de la pantalla, b = a la derecha
    final leftFirst = lsA.dx <= rsA.dx;
    final a = leftFirst ? lsA : rsA, b = leftFirst ? rsA : lsA;
    final sMid = (a + b) / 2;

    // caderas (si no se ven, se estiman con la proporción del cuerpo)
    final lhA = f.get(_L.leftHip), rhA = f.get(_L.rightHip);
    final hipsSeen = lhA != null && rhA != null;
    final rawShoulderPx = (b - a).distance;
    final torsoCm = 0.30 * body.height + 2.5; // costura del hombro → articulación de cadera
    Offset ha, hb;
    if (hipsSeen) {
      ha = leftFirst ? lhA : rhA;
      hb = leftFirst ? rhA : lhA;
    } else {
      final pxPerCm = math.max(rawShoulderPx, 10) / body.shoulder;
      final down = normalized(Offset(-(b - a).dy, (b - a).dx));
      final mid = sMid + down * (0.30 * body.height * pxPerCm);
      final half = (b - a) * 0.25;
      ha = mid - half;
      hb = mid + half;
    }
    final hipMid = (ha + hb) / 2;
    final torsoVec = hipMid - sMid;
    if (torsoVec.distance < 10) return 'Aléjate un poco para que se vea tu torso';

    // de perfil los hombros se juntan: se limita el angostamiento a la mitad
    final expectedShoulderPx = torsoVec.distance * body.shoulder / (0.30 * body.height);
    final shoulderPx = math.max(rawShoulderPx, 0.5 * expectedShoulderPx);
    final perpAxis = normalized(Offset(torsoVec.dy, -torsoVec.dx));
    final acrossS = rawShoulderPx > 0.4 * expectedShoulderPx ? normalized(b - a) : perpAxis;
    final upS = Offset(acrossS.dy, -acrossS.dx);
    final pxPerCm = shoulderPx / body.shoulder;
    final sTop = sMid + upS * (2.5 * pxPerCm);

    var acrossH = normalized(hb - ha);
    if (acrossH.dx * acrossS.dx + acrossH.dy * acrossS.dy < 0.3) acrossH = acrossS;
    final ratio = math.max((hb - ha).distance, 1) / shoulderPx;
    _hipRatioRef = _hipRatioRef == null ? ratio : _hipRatioRef! * 0.97 + ratio * 0.03;
    final twist = hipsSeen ? (ratio / _hipRatioRef!).clamp(0.8, 1.25) : 1.0;

    // ancho: hombros de la prenda ≈ 44 % del contorno de pecho de la talla
    final chest = size.chest ?? body.chest + 8;
    final widthRatio = ((chest * 0.44) / body.shoulder).clamp(0.95, 1.55);
    final sxS = shoulderPx * widthRatio / rig.anchorSpan;
    final sxH = sxS * twist;

    // largo: la fila de la imagen que cae en la cadera depende del largo de la talla
    final lengthCm = size.length ?? (rig.type == 'full' ? 98.0 : 70.0);
    final imgPxPerCm = (rig.bottom - rig.anchorY) / lengthCm;
    final hipRow = rig.anchorY + torsoCm * imgPxPerCm;
    final torso = hipMid - sTop;
    final vscale = torso.distance / (hipRow - rig.anchorY); // px de pantalla por px de imagen
    final axis = normalized(torso);

    var legDir = axis;
    final lk = f.get(_L.leftKnee), rk = f.get(_L.rightKnee);
    if (rig.type == 'full' && lk != null && rk != null) {
      legDir = normalized(normalized((lk + rk) / 2 - hipMid) + axis);
    }

    Offset map(Offset uv) {
      final v = uv.dy;
      final t = (v - rig.anchorY) / (hipRow - rig.anchorY);
      final center = t <= 1 ? sTop + torso * t : hipMid + legDir * ((v - hipRow) * vscale);
      final tc = t.clamp(0.0, 1.0);
      final across = normalized(Offset.lerp(acrossS, acrossH, tc)!);
      final sx = sxS + (sxH - sxS) * tc;
      return center + across * ((uv.dx - rig.centerX(v)) * sx);
    }

    _torsoGrid(mb, map);
    for (final limb in rig.limbs) {
      final anatLeft = (limb.side == 'l') == leftFirst;
      _limbStrip(
        mb,
        limb,
        map,
        origin: limb.side == 'l' ? a : b,
        joints: [f.get(anatLeft ? _L.leftElbow : _L.rightElbow), f.get(anatLeft ? _L.leftWrist : _L.rightWrist)],
        across: acrossS,
        up: upS,
        lengthScale: vscale,
        widthScale: vscale * 1.1,
        endSlack: 2 * pxPerCm,
      );
    }
    mb.pivot = sMid;
    return null;
  }

  // --------------------------------------------------- pantalones/faldas/shorts
  String? _fitBottom(BodyFrame f, SizeMeasures size, _MeshBuilder mb) {
    final lhA = f.get(_L.leftHip), rhA = f.get(_L.rightHip);
    if (lhA == null || rhA == null) return 'Muestra tu cadera y piernas a la cámara';
    final aIsLeft = lhA.dx <= rhA.dx; // ¿la cadera izquierda de la pantalla es la izquierda anatómica?
    final ha = aIsLeft ? lhA : rhA, hb = aIsLeft ? rhA : lhA;
    final hipMid = (ha + hb) / 2;
    final kA = f.get(aIsLeft ? _L.leftKnee : _L.rightKnee), kB = f.get(aIsLeft ? _L.rightKnee : _L.leftKnee);
    final anA = f.get(aIsLeft ? _L.leftAnkle : _L.rightAnkle), anB = f.get(aIsLeft ? _L.rightAnkle : _L.leftAnkle);

    // escala px/cm con las piernas (más estable) y la cadera
    double? legPxPerCm;
    if (anA != null && anB != null) {
      legPxPerCm = ((anA + anB) / 2 - hipMid).distance / (0.45 * body.height);
    } else if (kA != null && kB != null) {
      legPxPerCm = ((kA + kB) / 2 - hipMid).distance / (0.24 * body.height);
    }
    var hipPx = (hb - ha).distance;
    if (legPxPerCm != null) hipPx = math.max(hipPx, 0.5 * legPxPerCm * 0.19 * body.hip); // de perfil
    if (hipPx < 6) return 'Colócate de frente a la cámara';
    final hipPxPerCm = hipPx / (0.19 * body.hip);
    final pxPerCm = legPxPerCm == null ? hipPxPerCm : (hipPxPerCm + legPxPerCm) / 2;

    var legDir = Offset(0, 1);
    if (kA != null && kB != null) legDir = normalized((kA + kB) / 2 - hipMid);
    var across = (hb - ha).distance > 0.25 * hipPx ? normalized(hb - ha) : Offset(-legDir.dy, legDir.dx) * -1;
    if (across.dx < 0) across = -across;
    final up = Offset(across.dy, -across.dx);
    if (kA == null || kB == null) legDir = -up;

    // ancho de pretina ≈ 33 % del contorno de cintura de la talla
    final waist = size.waist ?? body.waist + 2;
    final widthRatio = ((waist * 0.33) / (body.hip * 0.19)).clamp(1.1, 2.1);
    final sx = hipPx * widthRatio / rig.anchorSpan;
    final lengthCm = size.length ?? 100;
    final imgPxPerCm = (rig.bottom - rig.anchorY) / lengthCm;
    final vscale = pxPerCm / imgPxPerCm;
    final hipRow = rig.anchorY + 9 * imgPxPerCm; // la pretina va ~9 cm sobre la cadera

    Offset map(Offset uv) {
      final v = uv.dy;
      final center = v <= hipRow ? hipMid + up * ((hipRow - v) * vscale) : hipMid + legDir * ((v - hipRow) * vscale);
      return center + across * ((uv.dx - rig.centerX(v)) * sx);
    }

    _torsoGrid(mb, map);
    for (final limb in rig.limbs) {
      final screenLeft = limb.side == 'l';
      _limbStrip(
        mb,
        limb,
        map,
        origin: screenLeft ? ha : hb,
        joints: screenLeft ? [kA, anA] : [kB, anB],
        across: across,
        up: up,
        lengthScale: vscale,
        widthScale: sx,
        endSlack: 6 * pxPerCm,
      );
    }
    mb.pivot = hipMid;
    return null;
  }

  // ------------------------------------------------------------------ mallas
  void _torsoGrid(_MeshBuilder mb, Offset Function(Offset) map) {
    const rows = 20, cols = 10;
    final grid = <List<(Offset, Offset)>>[];
    for (var r = 0; r <= rows; r++) {
      final v = rig.top + (rig.regionBottom - rig.top) * r / rows;
      final xl = rig.leftX(v), xr = rig.rightX(v);
      final row = <(Offset, Offset)>[];
      for (var c = 0; c <= cols; c++) {
        final uv = Offset(xl + (xr - xl) * c / cols, v);
        row.add((map(uv), uv));
      }
      grid.add(row);
    }
    mb.grid(grid);
  }

  /// Manga/pierna: tira que nace en el borde del torso (sisa o entrepierna) y,
  /// tras una transición suave, se monta sobre el eje real del miembro
  /// (hombro→codo→muñeca o cadera→rodilla→tobillo). Si no se ve el codo o la
  /// rodilla, conserva la pose de la ilustración.
  void _limbStrip(
    _MeshBuilder mb,
    LimbRig limb,
    Offset Function(Offset) map, {
    required Offset origin,
    required List<Offset?> joints,
    required Offset across,
    required Offset up,
    required double lengthScale,
    required double widthScale,
    required double endSlack,
  }) {
    final rootOuter = map(limb.rootOuter), rootInner = map(limb.rootInner);
    final rootMid = (rootOuter + rootInner) / 2;
    final restImg = limb.endMid - limb.rootMid;
    final restDir = normalized(across * restImg.dx - up * restImg.dy);
    var screenLen = limb.length * lengthScale;

    // eje del miembro desde la articulación de origen (hombro o cadera)
    final axisPts = <Offset>[origin];
    for (final j in joints) {
      if (j == null) break;
      if ((j - axisPts.last).distance > 3) axisPts.add(j);
    }
    final reachesEnd = axisPts.length == joints.length + 1;
    if (axisPts.length == 1) axisPts.add(origin + restDir * math.max(screenLen, 10));
    final axisPath = Polyline(axisPts);
    // a qué distancia del origen cae la raíz de la manga sobre ese eje
    final firstDir = normalized(axisPts[1] - axisPts[0]);
    final rel = rootMid - origin;
    final offset = (rel.dx * firstDir.dx + rel.dy * firstDir.dy).clamp(0.0, (axisPts[1] - axisPts[0]).distance * 0.8);
    // si se ve hasta la muñeca/tobillo, el puño/bajo termina ahí
    if (reachesEnd) screenLen = math.min(screenLen, axisPath.length - offset + endSlack);
    screenLen = math.max(screenLen, 4);

    // trayectoria paralela que arranca en la raíz (para coser la manga al torso)
    final rootPath = Polyline([rootMid, ...axisPts.skip(1)]);
    final window = screenLen * 0.08 + 1;
    final n0 = _normal(rootPath.tangentAt(0, window));
    final toOuter = rootOuter - rootMid;
    final sign = (n0.dx * toOuter.dx + n0.dy * toOuter.dy) >= 0 ? 1.0 : -1.0;

    // el ancho se mide perpendicular al eje de la manga/pierna en la imagen
    // (cerca de la raíz los bordes van desfasados: sisa diagonal)
    final imgNormal = _normal(normalized(restImg));
    const segs = 16;
    final strip = <(Offset, Offset, Offset, Offset)>[];
    for (var k = 0; k <= segs; k++) {
      final t = k / segs;
      final d = t * screenLen;
      final oUv = limb.outer.at(t * limb.outer.length), iUv = limb.inner.at(t * limb.inner.length);
      final onAxis = _smoothstep(t / 0.4);
      final c = Offset.lerp(rootPath.at(d), axisPath.at(offset + d), onAxis)!;
      final tangent = normalized(Offset.lerp(rootPath.tangentAt(d, window), axisPath.tangentAt(offset + d, window), onAxis)!);
      final n = _normal(tangent) * sign;
      final w = oUv - iUv;
      final hw = (w.dx * imgNormal.dx + w.dy * imgNormal.dy).abs() / 2 * widthScale;
      final stitch = _smoothstep(t / 0.3); // la raíz queda cosida al torso
      strip.add((Offset.lerp(rootOuter, c + n * hw, stitch)!, oUv, Offset.lerp(rootInner, c - n * hw, stitch)!, iUv));
    }
    mb.strip(strip);
  }

  static Offset _normal(Offset d) => Offset(-d.dy, d.dx);

  static double _smoothstep(double x) {
    final t = x.clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }
}

class _MeshBuilder {
  final _pos = <double>[];
  final _uv = <double>[];
  final _idx = <int>[];
  Offset pivot = Offset.zero;

  int get _count => _pos.length ~/ 2;
  bool get isEmpty => _idx.isEmpty;
  bool get isFinite => _pos.every((v) => v.isFinite);

  void _add(Offset p, Offset t) {
    _pos
      ..add(p.dx)
      ..add(p.dy);
    _uv
      ..add(t.dx)
      ..add(t.dy);
  }

  void grid(List<List<(Offset, Offset)>> g) {
    final base = _count, cols = g.first.length;
    for (final row in g) {
      for (final (p, t) in row) {
        _add(p, t);
      }
    }
    for (var r = 0; r < g.length - 1; r++) {
      for (var c = 0; c < cols - 1; c++) {
        final i0 = base + r * cols + c, i1 = i0 + 1, i2 = i0 + cols, i3 = i2 + 1;
        _idx.addAll([i0, i1, i2, i1, i3, i2]);
      }
    }
  }

  void strip(List<(Offset, Offset, Offset, Offset)> s) {
    final base = _count;
    for (final (po, to, pi, ti) in s) {
      _add(po, to);
      _add(pi, ti);
    }
    for (var k = 0; k < s.length - 1; k++) {
      final a = base + 2 * k, b = a + 1, c = a + 2, d = a + 3;
      _idx.addAll([a, b, c, b, d, c]);
    }
  }

  GarmentMesh build() =>
      GarmentMesh(Float32List.fromList(_pos), Float32List.fromList(_uv), Uint16List.fromList(_idx), pivot);
}
