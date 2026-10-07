import 'package:arfit/core/models.dart';
import 'package:arfit/core/sizing.dart';
import 'package:flutter_test/flutter_test.dart';

Product _product(String type, Map<String, Map<String, num>> chart) => Product.fromJson({
      'id': 'p', 'supplier_id': 's', 'name': 'n', 'category': 'polo', 'price': 1, 'image_url': 'x',
      'created_at': '2026-01-01T00:00:00Z', 'tryon_type': type, 'size_chart': chart,
      'stock': {for (final k in chart.keys) k: 5},
    });

void main() {
  test('estima contornos plausibles', () {
    final m = BodyMeasures.estimate(heightCm: 175, weightKg: 70, gender: 'hombre');
    expect(m.chest, closeTo(97.6, 1));
    expect(m.waist, closeTo(80.7, 1));
    expect(m.suggestedSize, 'M');
  });

  final polo = _product('top', {
    'S': {'chest': 96}, 'M': {'chest': 102}, 'L': {'chest': 108}, 'XL': {'chest': 114},
  });

  test('recomienda talla según pecho', () {
    final small = BodyMeasures.estimate(heightCm: 165, weightKg: 58, gender: 'hombre', chest: 90);
    final big = BodyMeasures.estimate(heightCm: 185, weightKg: 95, gender: 'hombre', chest: 106);
    expect(recommendSize(small, null, polo)!.size, 'S');
    expect(recommendSize(big, null, polo)!.size, 'XL');
  });

  test('detalle de calce marca ajustada / holgada', () {
    final body = BodyMeasures.estimate(heightCm: 175, weightKg: 70, chest: 96); // S +0, M +6, XL +18
    expect(fitDetails(body, polo.sizeChart['S']!, 'top').first.label, 'ajustada');
    expect(fitDetails(body, polo.sizeChart['M']!, 'top').first.label, 'ideal');
    expect(fitDetails(body, polo.sizeChart['XL']!, 'top').first.label, 'holgada');
  });
}
