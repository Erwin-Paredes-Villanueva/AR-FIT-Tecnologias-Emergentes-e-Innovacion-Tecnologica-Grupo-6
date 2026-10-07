// Estimación de medidas corporales y recomendación de talla.
// Espejo de supabase/functions/_shared/sizing.ts (misma lógica en servidor).
import 'dart:math' as math;

import 'models.dart';

class BodyMeasures {
  final double height, weight, chest, waist, hip, shoulder;
  final bool estimated;
  const BodyMeasures({
    required this.height,
    required this.weight,
    required this.chest,
    required this.waist,
    required this.hip,
    required this.shoulder,
    this.estimated = false,
  });

  double operator [](String zone) => switch (zone) {
        'chest' => chest,
        'waist' => waist,
        'hip' => hip,
        _ => 0,
      };

  /// Estima contornos a partir de altura, peso (IMC) y sexo cuando el usuario
  /// no los conoce. Relaciones antropométricas aproximadas.
  static BodyMeasures estimate({
    required double heightCm,
    required double weightKg,
    String? gender,
    double? chest,
    double? waist,
    double? hip,
    double? shoulder,
  }) {
    final h = heightCm;
    final bmiDelta = weightKg / math.pow(h / 100, 2) - 22;
    final female = gender == 'mujer';
    return BodyMeasures(
      height: h,
      weight: weightKg,
      chest: chest ?? (female ? 0.52 * h + 1.6 * bmiDelta : 0.55 * h + 1.5 * bmiDelta),
      waist: waist ?? (female ? 0.41 * h + 2.2 * bmiDelta : 0.45 * h + 2.2 * bmiDelta),
      hip: hip ?? (female ? 0.57 * h + 1.8 * bmiDelta : 0.53 * h + 1.6 * bmiDelta),
      shoulder: shoulder ?? (female ? 0.22 * h : 0.23 * h),
      estimated: chest == null || waist == null || hip == null,
    );
  }

  static BodyMeasures? fromProfile(Profile p) {
    if (p.heightCm == null || p.weightKg == null) return null;
    return estimate(
      heightCm: p.heightCm!,
      weightKg: p.weightKg!,
      gender: p.gender,
      chest: p.chestCm,
      waist: p.waistCm,
      hip: p.hipCm,
      shoulder: p.shoulderCm,
    );
  }

  /// Talla estándar sugerida a partir del contorno de pecho.
  String get suggestedSize {
    const limits = [84.0, 92.0, 100.0, 108.0, 116.0];
    for (var i = 0; i < limits.length; i++) {
      if (chest < limits[i]) return sizeOrder[i];
    }
    return 'XXL';
  }
}

/// Holgura ideal (contorno prenda - contorno cuerpo, cm) por zona.
const easeRange = {
  'chest': [4.0, 14.0],
  'waist': [0.0, 8.0],
  'hip': [2.0, 10.0],
};

List<String> zonesFor(String tryonType) => switch (tryonType) {
      'bottom' => ['waist', 'hip'],
      'full' => ['chest', 'waist', 'hip'],
      _ => ['chest'],
    };

class ZoneFit {
  final String zone;
  final double ease; // cm de holgura (negativo = aprieta)
  final String label;
  const ZoneFit(this.zone, this.ease, this.label);
}

const zoneNames = {'chest': 'pecho', 'waist': 'cintura', 'hip': 'cadera'};

/// Detalle del calce de una talla concreta sobre el cuerpo del usuario.
List<ZoneFit> fitDetails(BodyMeasures body, SizeMeasures m, String tryonType) {
  final out = <ZoneFit>[];
  for (final z in zonesFor(tryonType)) {
    final g = switch (z) { 'chest' => m.chest, 'waist' => m.waist, _ => m.hip };
    if (g == null) continue;
    final ease = g - body[z];
    final r = easeRange[z]!;
    final label = ease < r[0]
        ? 'ajustada'
        : ease > r[1]
            ? 'holgada'
            : 'ideal';
    out.add(ZoneFit(z, ease, label));
  }
  return out;
}

FitResult? recommendSize(BodyMeasures? body, String? declared, Product p, {bool onlyInStock = true}) {
  final sizes = onlyInStock ? p.sizesInStock : p.sizes;
  if (sizes.isEmpty) return null;
  if (body == null) {
    final s = declared != null && sizes.contains(declared) ? declared : sizes[sizes.length ~/ 2];
    return FitResult(s, 'ideal', declared != null ? 0.5 : 0.2);
  }
  String? best;
  double bestPenalty = double.infinity, bestEase = 0;
  for (final s in sizes) {
    final m = p.sizeChart[s]!;
    double penalty = 0, easeSum = 0;
    var n = 0;
    for (final z in zonesFor(p.tryonType)) {
      final g = switch (z) { 'chest' => m.chest, 'waist' => m.waist, _ => m.hip };
      if (g == null) continue;
      final ease = g - body[z];
      final r = easeRange[z]!;
      if (ease < r[0]) {
        penalty += (r[0] - ease) * 3;
      } else if (ease > r[1]) {
        penalty += ease - r[1];
      }
      easeSum += (ease - (r[0] + r[1]) / 2) / (r[1] - r[0]);
      n++;
    }
    if (n == 0) continue;
    if (penalty < bestPenalty) {
      bestPenalty = penalty;
      best = s;
      bestEase = easeSum / n;
    }
  }
  if (best == null) return null;
  final fit = bestEase < -0.5
      ? 'ajustada'
      : bestEase > 0.5
          ? 'holgada'
          : 'ideal';
  return FitResult(best, fit, math.max(0.3, 1 - bestPenalty / 30));
}
