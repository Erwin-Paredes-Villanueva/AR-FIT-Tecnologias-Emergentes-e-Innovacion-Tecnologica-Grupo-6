// Etiquetas anti-fraude de AR-FIT (verificación en 3 capas):
//   1) código de barras EAN-13 de la etiqueta (uno por talla)
//   2) QR único por unidad, firmado por AR-FIT → la app comprueba la firma
//      SIN servidor (recupera la dirección del firmante, como ecrecover)
//   3) registro y activación de la unidad en ARFitUnits (Polygon Amoy)
import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/ecc/curves/secp256k1.dart';

import 'chain_reader.dart';

// ------------------------------------------------------------------- EAN-13

/// Dígito de control GS1: pesos 1,3,1,3… sobre los 12 primeros dígitos.
int ean13CheckDigit(String first12) {
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    sum += int.parse(first12[i]) * (i.isEven ? 1 : 3);
  }
  return (10 - sum % 10) % 10;
}

bool isValidEan13(String code) =>
    RegExp(r'^[0-9]{13}$').hasMatch(code) && ean13CheckDigit(code.substring(0, 12)) == int.parse(code[12]);

const _l = ['0001101', '0011001', '0010011', '0111101', '0100011', '0110001', '0101111', '0111011', '0110111', '0001011'];
const _g = ['0100111', '0110011', '0011011', '0100001', '0011101', '0111001', '0000101', '0010001', '0001001', '0010111'];
const _r = ['1110010', '1100110', '1101100', '1000010', '1011100', '1001110', '1010000', '1000100', '1001000', '1110100'];
const _parity = ['LLLLLL', 'LLGLGG', 'LLGGLG', 'LLGGGL', 'LGLLGG', 'LGGLLG', 'LGGGLL', 'LGLGLG', 'LGLGGL', 'LGGLGL'];

/// Módulos del código EAN-13 (95 barras: '1' negra, '0' blanca) para dibujarlo.
String ean13Modules(String code) {
  assert(isValidEan13(code));
  final first = int.parse(code[0]);
  final b = StringBuffer('101');
  for (var i = 1; i <= 6; i++) {
    final d = int.parse(code[i]);
    b.write(_parity[first][i - 1] == 'L' ? _l[d] : _g[d]);
  }
  b.write('01010');
  for (var i = 7; i <= 12; i++) {
    b.write(_r[int.parse(code[i])]);
  }
  b.write('101');
  return b.toString();
}

// ---------------------------------------------------------------- etiqueta QR

/// Contenido del QR de una unidad:
/// `arfit://u/SERIE?p=UUID_PRENDA&t=TALLA&g=GTIN&s=FIRMA`
class UnitLabel {
  final String serial, productId, size, gtin, signature;
  const UnitLabel(this.serial, this.productId, this.size, this.gtin, this.signature);

  static UnitLabel? tryParse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != 'arfit' || uri.host != 'u' || uri.pathSegments.length != 1) return null;
    final q = uri.queryParameters;
    final p = q['p'], t = q['t'], g = q['g'], s = q['s'];
    if (p == null || t == null || g == null || s == null) return null;
    return UnitLabel(uri.pathSegments.first.toUpperCase(), p, t, g, s);
  }

  /// Mensaje que firmó AR-FIT al emitir la etiqueta (igual que en el servidor).
  String get message => 'ARFIT|$serial|$productId|$size|$gtin';

  /// Clave de la unidad en ARFitUnits.
  String get unitId => '0x${_hex(keccak256(utf8.encode(serial)))}';

  /// Dirección que firmó la etiqueta, o null si la firma está corrupta.
  String? get signer {
    try {
      return recoverPersonalSigner(message, signature);
    } catch (_) {
      return null;
    }
  }
}

// ------------------------------------------------------- firma (EIP-191)

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
BigInt _big(List<int> b) => BigInt.parse(_hex(b), radix: 16);

Uint8List _unhex(String h) {
  final s = h.startsWith('0x') ? h.substring(2) : h;
  return Uint8List.fromList(List.generate(s.length ~/ 2, (i) => int.parse(s.substring(i * 2, i * 2 + 2), radix: 16)));
}

/// Recupera la dirección Ethereum que firmó [message] con `personal_sign`
/// (EIP-191). Es la misma operación que `ecrecover` en Solidity o
/// `verifyMessage` en ethers: si alguien falsifica o altera la etiqueta,
/// la dirección recuperada no es la de AR-FIT.
String recoverPersonalSigner(String message, String signatureHex) {
  final sig = _unhex(signatureHex);
  if (sig.length != 65) throw const FormatException('La firma debe tener 65 bytes');
  final msg = utf8.encode(message);
  final hash = keccak256([...utf8.encode('\u0019Ethereum Signed Message:\n${msg.length}'), ...msg]);

  final params = ECCurve_secp256k1();
  final n = params.n;
  final r = _big(sig.sublist(0, 32));
  final s = _big(sig.sublist(32, 64));
  var v = sig[64];
  if (v >= 27) v -= 27;
  if (v > 1 || r <= BigInt.zero || r >= n || s <= BigInt.zero || s >= n) {
    throw const FormatException('Firma fuera de rango');
  }

  // R = punto de la curva con x = r y paridad de y = v
  final rPoint = params.curve.decompressPoint(v, r);
  final e = _big(hash);
  final rInv = r.modInverse(n);
  // Q = r⁻¹ (s·R − e·G)
  final q = (rPoint * ((s * rInv) % n))! + (params.G * ((n - e % n) * rInv % n))!;
  final pub = q!.getEncoded(false).sublist(1); // x‖y sin el prefijo 0x04
  final addr = keccak256(pub).sublist(12);
  return toChecksumAddress('0x${_hex(addr)}');
}

/// Dirección con mayúsculas de control (EIP-55), para mostrarla.
String toChecksumAddress(String address) {
  final a = address.toLowerCase().replaceFirst('0x', '');
  final h = _hex(keccak256(utf8.encode(a)));
  final out = StringBuffer('0x');
  for (var i = 0; i < a.length; i++) {
    out.write(int.parse(h[i], radix: 16) >= 8 ? a[i].toUpperCase() : a[i]);
  }
  return out.toString();
}
