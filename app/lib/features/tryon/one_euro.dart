// Filtro "One Euro" (Casiez et al., 2012): suaviza mucho cuando el punto está
// quieto (elimina el temblor de la detección) y casi nada cuando se mueve
// rápido (la prenda sigue el movimiento sin retraso).
import 'dart:math' as math;
import 'dart:ui';

class OneEuroFilter {
  OneEuroFilter({this.minCutoff = 1.5, this.beta = 0.02, this.dCutoff = 1.0});

  final double minCutoff, beta, dCutoff;
  double? _x, _dx, _t;

  static double _alpha(double cutoff, double dt) {
    final tau = 1 / (2 * math.pi * cutoff);
    return 1 / (1 + tau / dt);
  }

  double filter(double x, double t) {
    if (_t == null) {
      _t = t;
      _x = x;
      _dx = 0;
      return x;
    }
    final dt = math.max(1e-3, t - _t!);
    _t = t;
    final dx = (x - _x!) / dt;
    _dx = _dx! + _alpha(dCutoff, dt) * (dx - _dx!);
    final cutoff = minCutoff + beta * _dx!.abs();
    _x = _x! + _alpha(cutoff, dt) * (x - _x!);
    return _x!;
  }
}

class OneEuroFilter2D {
  final _x = OneEuroFilter();
  final _y = OneEuroFilter();

  Offset filter(Offset p, double t) => Offset(_x.filter(p.dx, t), _y.filter(p.dy, t));
}
