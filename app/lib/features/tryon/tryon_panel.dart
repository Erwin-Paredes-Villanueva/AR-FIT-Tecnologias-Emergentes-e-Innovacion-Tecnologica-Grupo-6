// Interfaz común de los probadores 2D (malla propia con ML Kit) y 3D (Snap
// Camera Kit): barra superior, temporizador, disparador, cuenta atrás y panel
// inferior con el ajuste por zona, las tallas y el carrito.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/labels.dart';
import '../../core/models.dart';
import '../../core/sizing.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Temporizador de la foto (sin, 5, 10 o 15 s) y su cuenta atrás.
class PhotoTimer extends ChangeNotifier {
  static const options = [0, 5, 10, 15];

  int seconds = 0;
  int? countdown; // segundos restantes mientras corre
  Timer? _timer;

  bool get counting => countdown != null;

  void cycle() {
    if (counting) return;
    seconds = options[(options.indexOf(seconds) + 1) % options.length];
    notifyListeners();
  }

  /// Dispara [shoot] de inmediato o al terminar la cuenta atrás.
  /// Si la cuenta ya corre, la cancela.
  void press(VoidCallback shoot) {
    if (counting) return cancel();
    if (seconds == 0) return shoot();
    countdown = seconds;
    SystemSound.play(SystemSoundType.click);
    notifyListeners();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = (countdown ?? 1) - 1;
      if (left <= 0) {
        t.cancel();
        countdown = null;
        notifyListeners();
        shoot();
      } else {
        countdown = left;
        if (left <= 3) HapticFeedback.lightImpact();
        SystemSound.play(SystemSoundType.click);
        notifyListeners();
      }
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    countdown = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

Widget tryOnRoundButton(IconData icon, VoidCallback onTap, {String? tooltip}) => Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: IconButton(tooltip: tooltip, icon: Icon(icon, color: Colors.white), onPressed: onTap),
    );

/// Barra superior: cerrar, prenda, modo del probador y acciones a la derecha.
class TryOnTopBar extends StatelessWidget {
  const TryOnTopBar({super.key, required this.title, required this.subtitle, this.actions = const []});
  final String title, subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(children: [
              tryOnRoundButton(Icons.close, () => Navigator.pop(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 6)])),
                  Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12, shadows: [Shadow(blurRadius: 6)])),
                ]),
              ),
              for (final a in actions) ...[a, const SizedBox(width: 8)],
            ]),
          ),
        ),
      );
}

/// Selector del temporizador (toca para cambiar entre Sin / 5 / 10 / 15 s).
class TimerButton extends StatelessWidget {
  const TimerButton({super.key, required this.timer});
  final PhotoTimer timer;

  @override
  Widget build(BuildContext context) {
    final on = timer.seconds > 0;
    return Semantics(
      button: true,
      label: on ? 'Temporizador de ${timer.seconds} segundos' : 'Temporizador desactivado',
      child: GestureDetector(
        onTap: () {
          if (timer.counting) return;
          timer.cycle();
          showInfo(context, timer.seconds == 0 ? 'Temporizador desactivado' : 'La foto se tomará ${timer.seconds} s después de tocar el botón');
        },
        child: Container(
          width: 64,
          height: 40,
          decoration: BoxDecoration(
            color: on ? Colors.white : Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white70),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(on ? Icons.timer_outlined : Icons.timer_off_outlined, size: 18, color: on ? AppColors.ink : Colors.white),
            if (on) ...[
              const SizedBox(width: 3),
              Text('${timer.seconds}s', style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700)),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Disparador: cámara blanca; naranja con ✕ durante la cuenta atrás.
class ShutterButton extends StatelessWidget {
  const ShutterButton({super.key, required this.timer, required this.busy, required this.onShoot});
  final PhotoTimer timer;
  final bool busy;
  final VoidCallback onShoot;

  @override
  Widget build(BuildContext context) {
    final counting = timer.counting;
    return Semantics(
      button: true,
      label: counting ? 'Cancelar temporizador' : 'Tomar foto',
      child: GestureDetector(
        onTap: busy ? null : () => timer.press(onShoot),
        child: Container(
          width: 72,
          height: 72,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: counting ? AppColors.accent : (busy ? Colors.white54 : Colors.white),
            ),
            child: busy
                ? const Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.ink))
                : counting
                    ? const Icon(Icons.close, color: Colors.white)
                    : const Icon(Icons.photo_camera, color: AppColors.ink),
          ),
        ),
      ),
    );
  }
}

/// Número grande de la cuenta atrás en el centro de la pantalla.
class CountdownOverlay extends StatelessWidget {
  const CountdownOverlay({super.key, required this.timer});
  final PhotoTimer timer;

  @override
  Widget build(BuildContext context) {
    final n = timer.countdown;
    if (n == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: Center(
        child: TweenAnimationBuilder<double>(
          key: ValueKey(n),
          tween: Tween(begin: 1.35, end: 1),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
          child: Container(
            width: 150,
            height: 150,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withValues(alpha: 0.45)),
            child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 76, fontWeight: FontWeight.w800, height: 1)),
          ),
        ),
      ),
    );
  }
}

/// Destello blanco al tomar la foto.
class FlashOverlay extends StatelessWidget {
  const FlashOverlay({super.key, required this.visible});
  final bool visible;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedOpacity(
          opacity: visible ? 0.85 : 0,
          duration: const Duration(milliseconds: 120),
          child: Container(color: Colors.white),
        ),
      );
}

/// Panel inferior: temporizador + disparador, ajuste por zona de la talla
/// elegida, selector de tallas, "Elegir talla" y "Al carrito".
class TryOnBottomPanel extends StatelessWidget {
  const TryOnBottomPanel({
    super.key,
    required this.product,
    required this.body,
    required this.size,
    required this.onSize,
    required this.timer,
    required this.capturing,
    required this.onShoot,
    required this.showShutter,
    required this.footnote,
  });

  final Product product;
  final BodyMeasures body;
  final String? size;
  final ValueChanged<String> onSize;
  final PhotoTimer timer;
  final bool capturing;
  final VoidCallback onShoot;
  final bool showShutter;
  final String footnote;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final state = context.read<AppState>();
    final rec = recommendSize(state.body, state.profile?.size, p);
    final measures = size == null ? null : p.sizeChart[size];
    final details = measures == null ? <ZoneFit>[] : fitDetails(body, measures, p.tryonType);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
        ),
      ),
      padding: EdgeInsets.fromLTRB(16, 40, 16, MediaQuery.of(context).padding.bottom + 14),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (showShutter)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              TimerButton(timer: timer),
              const SizedBox(width: 22),
              ShutterButton(timer: timer, busy: capturing, onShoot: onShoot),
              const SizedBox(width: 86), // equilibra el selector para centrar el disparador
            ]),
          ),
        if (details.isNotEmpty)
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final d in details)
              Pill(
                '${zoneNames[d.zone]}: ${fitLabels[d.label]!.toLowerCase()} ${d.ease >= 0 ? '+' : ''}${d.ease.round()} cm',
                color: switch (d.label) { 'ideal' => AppColors.chain, 'ajustada' => Colors.orange, _ => AppColors.ar },
                filled: true,
              ),
            if (measures?.length != null) Pill('largo ${measures!.length!.round()} cm', color: Colors.white24, filled: true),
          ]),
        const SizedBox(height: 10),
        Row(children: [
          const Text('Talla', style: TextStyle(color: Colors.white70)),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final s in p.sizes)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(s),
                        if (rec?.size == s) ...[const SizedBox(width: 3), const Icon(Icons.auto_awesome, size: 13, color: AppColors.ai)],
                      ]),
                      selected: size == s,
                      onSelected: (_) => onSize(s),
                    ),
                  ),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
              onPressed: () => Navigator.pop(context, size),
              child: Text('Elegir talla ${size ?? ''}'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: BusyButton(
              label: 'Al carrito',
              icon: Icons.add_shopping_cart,
              color: AppColors.accent,
              onPressed: size == null || (p.stock[size] ?? 0) == 0
                  ? null
                  : () async {
                      await Api.addToCart(p.id, size!);
                      await state.refreshCart();
                      if (context.mounted) showInfo(context, 'Talla $size agregada al carrito');
                    },
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text(footnote, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ]),
    );
  }
}
