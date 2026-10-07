// Verificación contra Polygon Amoy real:  flutter test test/live_chain_test.dart (requiere test/live_products.json)
import 'dart:convert';
import 'dart:io';

import 'package:arfit/core/chain_reader.dart';
import 'package:arfit/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final file = File('test/live_products.json');
  test('las prendas en Amoy coinciden con la base de datos', () async {
    final rows = (jsonDecode(file.readAsStringSync()) as List).cast<Map<String, dynamic>>();
    expect(rows, isNotEmpty);
    final reader = ChainReader();
    for (final r in rows) {
      final p = Product.fromJson(r);
      final c = await reader.getProduct(p.id);
      // ignore: avoid_print
      print('${p.name}: on-chain=${c.exists} verificada=${c.verified} origen="${c.origin}" hash ok=${c.dataHash == productDataHash(p)}');
      expect(c.exists && c.verified, isTrue);
      expect(c.dataHash, productDataHash(p));
    }
    // ignore: avoid_print
    print('bloque actual: ${await reader.latestBlock()}');
  }, skip: file.existsSync() ? null : 'sin datos');
}
