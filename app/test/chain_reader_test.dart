// Prueba de lectura/decodificación del contrato contra un nodo EVM.
// Requiere un nodo con datos de ejemplo:  CHAIN_TEST_RPC=... CHAIN_TEST_ADDRESS=... flutter test
import 'dart:io';

import 'package:arfit/core/chain_reader.dart';
import 'package:arfit/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rpc = Platform.environment['CHAIN_TEST_RPC'];
  final address = Platform.environment['CHAIN_TEST_ADDRESS'];
  final skip = rpc == null || address == null ? 'sin nodo de prueba' : null;
  const pid = '11111111-2222-3333-4444-555555555555';
  const oid = '99999999-8888-7777-6666-555555555555';

  test('chainRef = keccak256(utf8(uuid))', () {
    expect(chainRef('abc'), '0x4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45');
  });

  test('lee y verifica una prenda', () async {
    final reader = ChainReader(rpcUrl: rpc, contract: address);
    final c = await reader.getProduct(pid);
    expect(c.exists, isTrue);
    expect(c.verified, isTrue);
    expect(c.name, 'Polo básico Pima');
    expect(c.origin, 'Gamarra, Lima - Perú');
    final p = Product.fromJson({
      'id': pid, 'supplier_id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee', 'name': 'Polo básico Pima',
      'brand': 'Andina Wear', 'category': 'polo', 'color': 'blanco', 'price': 59.9,
      'origin': 'Gamarra, Lima - Perú', 'materials': '100% algodón pima peruano',
      'image_url': 'x', 'created_at': '2026-01-01T00:00:00Z',
    });
    expect(productDataHash(p), c.dataHash);
    expect((await reader.getProduct('no-existe')).exists, isFalse);
  }, skip: skip);

  test('lee el historial de un pedido', () async {
    final o = await ChainReader(rpcUrl: rpc, contract: address).getOrder(oid);
    expect(o.exists, isTrue);
    expect(o.status, 'prepared');
    expect(o.productCount, 1);
    expect(o.events.map((e) => e.status), ['created', 'prepared']);
    expect(o.events.last.note, 'Empacado ✓');
    expect(o.events.last.actorRole, 'proveedor');
  }, skip: skip);
}
