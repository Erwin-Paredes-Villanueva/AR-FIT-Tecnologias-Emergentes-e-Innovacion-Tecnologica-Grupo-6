import 'package:arfit/core/unit_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('EAN-13: dígito de control y validación', () {
    expect(ean13CheckDigit('400638133393'), 1);
    expect(isValidEan13('4006381333931'), isTrue);
    expect(isValidEan13('4006381333932'), isFalse);
    expect(isValidEan13('12345'), isFalse);
  });

  test('EAN-13: patrón de barras estándar (95 módulos)', () {
    final m = ean13Modules('4006381333931');
    expect(m.length, 95);
    expect(m.startsWith('101'), isTrue);
    expect(m.substring(45, 50), '01010');
    expect(m.endsWith('101'), isTrue);
  });

  // Vector generado con ethers v6: Wallet('0x11…11').signMessage(mensaje)
  const message = 'ARFIT|AF7K-2M9Q-X4PT|2b7c0d3e-0000-4000-8000-000000000001|M|7750202600011';
  const signature =
      '0x5abf41fa714f331466fd871d8b04ea9e43703c945c16a9a2cd3566e8af75e2295b7c832338b7c0600a1bdc4947f11bd2cb3912464f79d8bce3f1a9195fc7d7881c';
  const signer = '0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A';

  test('firma EIP-191: recupera la dirección del emisor', () {
    expect(recoverPersonalSigner(message, signature), signer);
  });

  test('firma EIP-191: una etiqueta alterada no conserva el emisor', () {
    expect(recoverPersonalSigner(message.replaceFirst('|M|', '|L|'), signature), isNot(signer));
  });

  test('QR de unidad: se interpreta y valida la firma', () {
    final label = UnitLabel.tryParse(
        'arfit://u/AF7K-2M9Q-X4PT?p=2b7c0d3e-0000-4000-8000-000000000001&t=M&g=7750202600011&s=$signature');
    expect(label, isNotNull);
    expect(label!.serial, 'AF7K-2M9Q-X4PT');
    expect(label.message, message);
    expect(label.signer, signer);
    expect(UnitLabel.tryParse('arfit://product/abc'), isNull);
    expect(UnitLabel.tryParse('https://example.com'), isNull);
  });
}
