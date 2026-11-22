import 'package:flutter/material.dart';

import '../core/unit_label.dart';

/// Código de barras EAN-13 dibujado a partir de su patrón estándar de 95
/// módulos, con los dígitos debajo (formato de etiqueta comercial).
class Ean13Barcode extends StatelessWidget {
  const Ean13Barcode(this.code, {super.key, this.height = 64, this.moduleWidth = 2});
  final String code;
  final double height;
  final double moduleWidth;

  @override
  Widget build(BuildContext context) {
    if (!isValidEan13(code)) return Text('Código inválido: $code', style: const TextStyle(color: Colors.red));
    final w = moduleWidth * (95 + 18); // márgenes en blanco a los lados
    return SizedBox(
      width: w,
      height: height + 16,
      child: CustomPaint(painter: _Ean13Painter(ean13Modules(code), code, moduleWidth, height)),
    );
  }
}

class _Ean13Painter extends CustomPainter {
  _Ean13Painter(this.modules, this.code, this.mw, this.h);
  final String modules, code;
  final double mw, h;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final black = Paint()..color = Colors.black;
    final left = mw * 11;
    for (var i = 0; i < modules.length; i++) {
      if (modules[i] != '1') continue;
      // las barras de guarda (inicio, centro y fin) bajan un poco más
      final guard = i < 3 || (i >= 45 && i < 50) || i >= 92;
      canvas.drawRect(Rect.fromLTWH(left + i * mw, 0, mw, guard ? h + 8 : h), black);
    }
    final style = TextStyle(color: Colors.black, fontSize: mw * 6.2, fontFamily: 'monospace', height: 1);
    void text(String s, double x, double width) {
      final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)
        ..layout(minWidth: width, maxWidth: width);
      tp.paint(canvas, Offset(x, h + 1));
    }

    text(code[0], 0, left - mw);
    text(code.substring(1, 7), left + 3 * mw, 42 * mw);
    text(code.substring(7), left + 50 * mw, 42 * mw);
  }

  @override
  bool shouldRepaint(_Ean13Painter old) => old.code != code || old.mw != mw || old.h != h;
}
