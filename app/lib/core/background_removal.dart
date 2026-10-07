// Quita el fondo liso de una foto de producto para usarla en el probador RA.
// Relleno por inundación desde los bordes con tolerancia de color: funciona
// bien con fotos de estudio sobre fondo blanco o de un solo color.

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

Future<Uint8List> removeBackground(Uint8List bytes, {int tolerance = 38}) =>
    compute(_remove, (bytes: bytes, tolerance: tolerance));

Uint8List _remove(({Uint8List bytes, int tolerance}) args) {
  var src = img.decodeImage(args.bytes);
  if (src == null) throw Exception('Imagen no válida');
  if (src.width > 1000 || src.height > 1000) {
    src = img.copyResize(src, width: src.width >= src.height ? 1000 : null, height: src.height > src.width ? 1000 : null);
  }
  final image = src.convert(numChannels: 4);
  final w = image.width, h = image.height;

  // color de fondo = promedio de las esquinas
  double r = 0, g = 0, b = 0;
  for (final (x, y) in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]) {
    final p = image.getPixel(x, y);
    r += p.r;
    g += p.g;
    b += p.b;
  }
  r /= 4;
  g /= 4;
  b /= 4;
  final tol2 = args.tolerance * args.tolerance * 3;

  bool isBg(int x, int y) {
    final p = image.getPixel(x, y);
    final dr = p.r - r, dg = p.g - g, db = p.b - b;
    return dr * dr + dg * dg + db * db <= tol2;
  }

  final visited = Uint8List(w * h);
  final stack = <int>[];
  void push(int x, int y) {
    final i = y * w + x;
    if (visited[i] == 0 && isBg(x, y)) {
      visited[i] = 1;
      stack.add(i);
    }
  }

  for (var x = 0; x < w; x++) {
    push(x, 0);
    push(x, h - 1);
  }
  for (var y = 0; y < h; y++) {
    push(0, y);
    push(w - 1, y);
  }
  while (stack.isNotEmpty) {
    final i = stack.removeLast();
    final x = i % w, y = i ~/ w;
    if (x > 0) push(x - 1, y);
    if (x < w - 1) push(x + 1, y);
    if (y > 0) push(x, y - 1);
    if (y < h - 1) push(x, y + 1);
  }

  var minX = w, minY = h, maxX = 0, maxY = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (visited[y * w + x] == 1) {
        image.getPixel(x, y).a = 0;
      } else {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX <= minX || maxY <= minY) return img.encodePng(image);
  final cropped = img.copyCrop(image, x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1);
  return img.encodePng(cropped);
}
