// Lectura directa del contrato ARFitTrace en Polygon Amoy vía JSON-RPC público.
// La app verifica la autenticidad SIN pasar por nuestro backend: consulta la
// cadena y compara la huella (sha256) de la ficha con la registrada on-chain.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:pointycastle/digests/keccak.dart';

import '../config.dart';
import 'models.dart';

String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _unhex(String h) {
  final s = h.startsWith('0x') ? h.substring(2) : h;
  return Uint8List.fromList(List.generate(s.length ~/ 2, (i) => int.parse(s.substring(i * 2, i * 2 + 2), radix: 16)));
}

Uint8List keccak256(List<int> input) {
  final d = KeccakDigest(256);
  return d.process(Uint8List.fromList(input));
}

/// UUID → bytes32, igual que en las Edge Functions (keccak256(utf8(uuid))).
String chainRef(String uuid) => '0x${_hex(keccak256(utf8.encode(uuid)))}';

/// Huella de la ficha de la prenda (idéntica a productDataHash del servidor).
String productDataHash(Product p) {
  final canonical = [p.id, p.supplierId, p.name, p.brand, p.category, p.color, p.origin, p.materials].join('|');
  return '0x${crypto.sha256.convert(utf8.encode(canonical))}';
}

const chainStatuses = ['created', 'prepared', 'picked_up', 'in_transit', 'delivered', 'received', 'cancelled'];

class ChainProduct {
  final bool exists;
  final String supplierRef, name, origin, materials, dataHash;
  final DateTime registeredAt;
  final bool verified;
  ChainProduct(this.exists, this.supplierRef, this.name, this.origin, this.materials, this.dataHash,
      this.registeredAt, this.verified);
}

class ChainEvent {
  final String status, location, actorRole, actorRef, note;
  final DateTime timestamp;
  ChainEvent(this.status, this.location, this.actorRole, this.actorRef, this.note, this.timestamp);
}

class ChainOrder {
  final bool exists;
  final String buyerRef, supplierRef, status;
  final DateTime createdAt;
  final int productCount;
  final List<ChainEvent> events;
  ChainOrder(this.exists, this.buyerRef, this.supplierRef, this.status, this.createdAt, this.productCount, this.events);
}

class _Abi {
  final Uint8List data;
  _Abi(this.data);
  Uint8List word(int i) => data.sublist(i * 32, i * 32 + 32);
  BigInt uint(int i) => BigInt.parse(_hex(word(i)), radix: 16);
  int integer(int i) => uint(i).toInt();
  bool boolean(int i) => uint(i) != BigInt.zero;
  String bytes32(int i) => '0x${_hex(word(i))}';
  String string(int i) {
    final offset = integer(i);
    final len = BigInt.parse(_hex(data.sublist(offset, offset + 32)), radix: 16).toInt();
    return utf8.decode(data.sublist(offset + 32, offset + 32 + len));
  }
}

class ChainReader {
  ChainReader({http.Client? client, String? rpcUrl, String? contract})
      : _http = client ?? http.Client(),
        _rpcUrl = rpcUrl ?? AppConfig.amoyRpcUrl,
        _contract = contract ?? AppConfig.contractAddress;
  final http.Client _http;
  final String _rpcUrl;
  final String _contract;
  int _id = 0;

  String _selector(String signature) => _hex(keccak256(utf8.encode(signature)).sublist(0, 4));
  String _word(BigInt v) => v.toRadixString(16).padLeft(64, '0');

  Future<dynamic> _rpc(String method, List<dynamic> params) async {
    final res = await _http.post(
      Uri.parse(_rpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'jsonrpc': '2.0', 'id': ++_id, 'method': method, 'params': params}),
    );
    final body = jsonDecode(res.body);
    if (body['error'] != null) throw Exception(body['error']['message']);
    return body['result'];
  }

  Future<_Abi> _call(String signature, List<String> encodedArgs) async {
    final data = '0x${_selector(signature)}${encodedArgs.join()}';
    final result = await _rpc('eth_call', [
      {'to': _contract, 'data': data},
      'latest',
    ]);
    return _Abi(_unhex(result as String));
  }

  String _b32(String hex) => (hex.startsWith('0x') ? hex.substring(2) : hex).padLeft(64, '0');

  Future<ChainProduct> getProduct(String productUuid) async {
    final r = await _call('getProduct(bytes32)', [_b32(chainRef(productUuid))]);
    return ChainProduct(
      r.boolean(0),
      r.bytes32(1),
      r.string(2),
      r.string(3),
      r.string(4),
      r.bytes32(5),
      DateTime.fromMillisecondsSinceEpoch(r.integer(6) * 1000),
      r.boolean(7),
    );
  }

  Future<ChainOrder> getOrder(String orderUuid) async {
    final id = _b32(chainRef(orderUuid));
    final r = await _call('getOrder(bytes32)', [id]);
    final count = r.integer(6);
    final events = <ChainEvent>[];
    for (var i = 0; i < count; i++) {
      final e = await _call('getOrderEvent(bytes32,uint256)', [id, _word(BigInt.from(i))]);
      events.add(ChainEvent(
        chainStatuses[e.integer(0)],
        e.string(1),
        e.string(2),
        e.bytes32(3),
        e.string(4),
        DateTime.fromMillisecondsSinceEpoch(e.integer(5) * 1000),
      ));
    }
    return ChainOrder(
      r.boolean(0),
      r.bytes32(1),
      r.bytes32(2),
      chainStatuses[r.integer(3)],
      DateTime.fromMillisecondsSinceEpoch(r.integer(4) * 1000),
      r.integer(5),
      events,
    );
  }

  /// Número de bloque y estado de una transacción (para mostrar confirmaciones).
  Future<({int block, bool success})?> receipt(String txHash) async {
    final r = await _rpc('eth_getTransactionReceipt', [txHash]);
    if (r == null) return null;
    return (block: int.parse((r['blockNumber'] as String).substring(2), radix: 16), success: r['status'] == '0x1');
  }

  Future<int> latestBlock() async {
    final r = await _rpc('eth_blockNumber', []);
    return int.parse((r as String).substring(2), radix: 16);
  }
}
