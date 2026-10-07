import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../theme.dart';

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red.shade700),
  );
}

void showInfo(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

Future<void> openExplorerTx(String txHash) =>
    launchUrl(Uri.parse('${AppConfig.explorerUrl}/tx/$txHash'), mode: LaunchMode.externalApplication);

Future<void> openExplorerContract() =>
    launchUrl(Uri.parse('${AppConfig.explorerUrl}/address/${AppConfig.contractAddress}'),
        mode: LaunchMode.externalApplication);

String shortHash(String h, [int n = 6]) => h.length <= n * 2 + 2 ? h : '${h.substring(0, n + 2)}…${h.substring(h.length - n)}';

/// Imagen de prenda sobre fondo suave (las ilustraciones tienen fondo transparente).
class GarmentImage extends StatelessWidget {
  const GarmentImage(this.url, {super.key, this.padding = 14, this.radius = 18, this.background});
  final String url;
  final double padding;
  final double radius;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [background ?? const Color(0xFFEFEBE4), const Color(0xFFE4DED5)],
          ),
        ),
        padding: EdgeInsets.all(padding),
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.contain,
          placeholder: (_, _) => const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          errorWidget: (_, _, _) => const Icon(Icons.checkroom, size: 48, color: AppColors.muted),
        ),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = AppColors.ink, this.icon, this.filled = false});
  final String text;
  final Color color;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: filled ? Colors.white : color), const SizedBox(width: 4)],
        Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: filled ? Colors.white : color)),
      ]),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(subtitle!, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
              ),
          ]),
        ),
        ?trailing,
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: AppColors.muted.withValues(alpha: 0.6)),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
          ],
          if (action != null) ...[const SizedBox(height: 18), action!],
        ]),
      ),
    );
  }
}

/// Botón que muestra un spinner mientras corre la acción asíncrona.
class BusyButton extends StatefulWidget {
  const BusyButton({super.key, required this.label, required this.onPressed, this.icon, this.outlined = false, this.color});
  final String label;
  final IconData? icon;
  final Future<void> Function()? onPressed;
  final bool outlined;
  final Color? color;

  @override
  State<BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<BusyButton> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = _busy
        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            if (widget.icon != null) ...[Icon(widget.icon, size: 19), const SizedBox(width: 8)],
            Flexible(child: Text(widget.label, overflow: TextOverflow.ellipsis)),
          ]);
    final onPressed = widget.onPressed == null || _busy ? null : _run;
    if (widget.outlined) {
      return OutlinedButton(onPressed: onPressed, child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2)) : child);
    }
    return FilledButton(
      style: widget.color == null ? null : FilledButton.styleFrom(backgroundColor: widget.color),
      onPressed: onPressed,
      child: child,
    );
  }
}

class Logo extends StatelessWidget {
  const Logo({super.key, this.size = 30, this.light = false});
  final double size;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final c = light ? Colors.white : AppColors.ink;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: size * 1.2,
        height: size * 1.2,
        decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(size * 0.35)),
        child: Icon(Icons.view_in_ar_rounded, color: Colors.white, size: size * 0.8),
      ),
      SizedBox(width: size * 0.35),
      Text('AR-FIT', style: TextStyle(fontSize: size * 0.9, fontWeight: FontWeight.w800, color: c, letterSpacing: -0.5)),
    ]);
  }
}
