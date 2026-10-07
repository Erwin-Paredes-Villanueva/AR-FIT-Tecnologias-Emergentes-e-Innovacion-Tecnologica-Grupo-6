// "Rig" de una prenda: puntos clave de la imagen que permiten deformarla con el
// esqueleto detectado (torso + mangas o piernas), como en la animación 2D por
// huesos. Lo generan tools/garments/generate.py (catálogo demo) y, para fotos
// subidas por proveedores, se estima a partir del contorno de la imagen.
import 'dart:math' as math;
import 'dart:ui';

Offset normalized(Offset v) {
  final d = v.distance;
  return d < 1e-9 ? const Offset(0, 1) : v / d;
}

/// Polilínea parametrizada por longitud de arco (se extrapola en los extremos).
class Polyline {
  Polyline(this.points) : assert(points.length >= 2) {
    _cum = [0];
    for (var i = 1; i < points.length; i++) {
      _cum.add(_cum.last + (points[i] - points[i - 1]).distance);
    }
  }

  final List<Offset> points;
  late final List<double> _cum;

  double get length => _cum.last;

  Offset at(double d) {
    if (length < 1e-9) return points.first;
    if (d <= 0) return points[0] + normalized(points[1] - points[0]) * d;
    if (d >= length) {
      final n = points.length;
      return points[n - 1] + normalized(points[n - 1] - points[n - 2]) * (d - length);
    }
    var i = 1;
    while (_cum[i] < d) {
      i++;
    }
    final seg = _cum[i] - _cum[i - 1];
    final t = seg < 1e-9 ? 0.0 : (d - _cum[i - 1]) / seg;
    return Offset.lerp(points[i - 1], points[i], t)!;
  }

  /// Tangente suavizada (promedia alrededor de las articulaciones).
  Offset tangentAt(double d, double window) => normalized(at(d + window) - at(d - window));
}

/// Manga o pierna: bordes exterior e interior desde la unión con el torso
/// (raíz) hasta el puño o el bajo, en píxeles de la imagen.
class LimbRig {
  LimbRig({required this.side, required this.kind, required this.outer, required this.inner});

  final String side; // 'l' | 'r': lado izquierdo/derecho de la imagen
  final String kind; // 'arm' | 'leg'
  final Polyline outer;
  final Polyline inner;

  Offset get rootOuter => outer.points.first;
  Offset get rootInner => inner.points.first;
  Offset get rootMid => (rootOuter + rootInner) / 2;
  Offset get endMid => (outer.points.last + inner.points.last) / 2;
  double get length => (endMid - rootMid).distance;
}

class GarmentRig {
  GarmentRig({
    required this.type,
    required this.top,
    required this.bottom,
    required this.regionBottom,
    required this.anchorL,
    required this.anchorR,
    required this.edgeL,
    required this.edgeR,
    required this.limbs,
  });

  /// top (polos, camisas, casacas) · full (vestidos) · bottom (pantalones, faldas)
  final String type;
  final double top, bottom, regionBottom;

  /// Costuras de hombro (top/full) o extremos de la pretina (bottom).
  final Offset anchorL, anchorR;

  /// Bordes laterales del torso/cintura, de arriba hacia abajo.
  final List<Offset> edgeL, edgeR;
  final List<LimbRig> limbs;

  double get anchorY => (anchorL.dy + anchorR.dy) / 2;
  double get anchorSpan => math.max(1, (anchorR - anchorL).distance);

  double leftX(double y) => _xAt(edgeL, y);
  double rightX(double y) => _xAt(edgeR, y);
  double centerX(double y) => (leftX(y) + rightX(y)) / 2;

  static double _xAt(List<Offset> edge, double y) {
    if (y <= edge.first.dy) return edge.first.dx;
    if (y >= edge.last.dy) return edge.last.dx;
    for (var i = 1; i < edge.length; i++) {
      if (y <= edge[i].dy) {
        final a = edge[i - 1], b = edge[i];
        final t = (b.dy - a.dy).abs() < 1e-9 ? 0.0 : (y - a.dy) / (b.dy - a.dy);
        return a.dx + (b.dx - a.dx) * t;
      }
    }
    return edge.last.dx;
  }

  /// Rig a partir del JSON normalizado (0..1) guardado en `products.tryon_rig`.
  static GarmentRig? fromJson(Map<String, dynamic>? json, Size image) {
    if (json == null) return null;
    try {
      Offset pt(dynamic v) {
        final l = v as List;
        return Offset((l[0] as num).toDouble() * image.width, (l[1] as num).toDouble() * image.height);
      }

      List<Offset> pts(dynamic v) => (v as List).map(pt).toList();
      double y(String k) => (json[k] as num).toDouble() * image.height;
      return GarmentRig(
        type: json['type'] as String,
        top: y('top'),
        bottom: y('bottom'),
        regionBottom: y('region_bottom'),
        anchorL: pt(json['anchor_l']),
        anchorR: pt(json['anchor_r']),
        edgeL: pts(json['edge_l']),
        edgeR: pts(json['edge_r']),
        limbs: [
          for (final l in (json['limbs'] as List? ?? const []))
            LimbRig(
              side: l['side'] as String,
              kind: l['kind'] as String,
              outer: Polyline(pts(l['outer'])),
              inner: Polyline(pts(l['inner'])),
            ),
        ],
      );
    } catch (_) {
      return null;
    }
  }

  /// Rig aproximado para fotos sin rig (subidas por proveedores): toda la prenda
  /// se trata como torso/cintura, que igualmente se deforma con el cuerpo.
  static GarmentRig fallback({
    required Rect opaque,
    required String tryonType,
    Map<String, List<double>>? anchor,
    required Size image,
  }) {
    Offset inBox(double x, double y) => Offset(opaque.left + x * opaque.width, opaque.top + y * opaque.height);
    final defaults = switch (tryonType) {
      'bottom' => (inBox(0.10, 0.0), inBox(0.90, 0.0)),
      'full' => (inBox(0.28, 0.01), inBox(0.72, 0.01)),
      _ => (inBox(0.26, 0.04), inBox(0.74, 0.04)),
    };
    var (l, r) = defaults;
    if (anchor?['l'] != null && anchor?['r'] != null) {
      l = Offset(anchor!['l']![0] * image.width, anchor['l']![1] * image.height);
      r = Offset(anchor['r']![0] * image.width, anchor['r']![1] * image.height);
    }
    return GarmentRig(
      type: tryonType,
      top: opaque.top,
      bottom: opaque.bottom,
      regionBottom: opaque.bottom,
      anchorL: l,
      anchorR: r,
      edgeL: [opaque.topLeft, opaque.bottomLeft],
      edgeR: [opaque.topRight, opaque.bottomRight],
      limbs: const [],
    );
  }
}
