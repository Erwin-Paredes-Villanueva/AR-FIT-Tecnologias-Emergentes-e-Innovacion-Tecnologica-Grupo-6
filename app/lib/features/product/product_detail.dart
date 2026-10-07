import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/labels.dart';
import '../../core/models.dart';
import '../../core/sizing.dart';
import '../../core/snap_tryon.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../cart/cart_screen.dart';
import '../tryon/tryon_screen.dart';
import '../verify/authenticity_card.dart';

class ProductDetail extends StatefulWidget {
  const ProductDetail({super.key, required this.product});
  final Product product;

  @override
  State<ProductDetail> createState() => _ProductDetailState();
}

class _ProductDetailState extends State<ProductDetail> {
  late Product p = widget.product;
  String? _size;
  PublicProfile? _supplier;
  bool _snapReady = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    if (state.profile!.isBuyer) Api.track(p.id, 'view');
    _size = recommendSize(state.body, state.profile!.size, p)?.size;
    if (p.tryonLensId != null) {
      SnapTryOn.isAvailable().then((ok) => mounted ? setState(() => _snapReady = ok) : null);
    }
    Api.publicProfiles().then((list) {
      if (!mounted) return;
      setState(() => _supplier = list.where((x) => x.id == p.supplierId).firstOrNull);
    });
  }

  Future<void> _addToCart() async {
    if (_size == null) throw Exception('Selecciona una talla');
    await Api.addToCart(p.id, _size!);
    if (!mounted) return;
    await context.read<AppState>().refreshCart();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${p.name} (talla $_size) agregado al carrito'),
      action: SnackBarAction(
        label: 'Ver carrito',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen())),
      ),
    ));
  }

  /// Probador 3D (Snap): prenda con volumen y simulación de tela en cámara en vivo.
  Future<void> _openTryOn3D() async {
    Api.track(p.id, 'tryon');
    final res = await SnapTryOn.launch(p.tryonLensId!);
    if (!mounted) return;
    if (res.status == 'failure') {
      showError(context, 'No se pudo abrir el probador 3D: ${res.error ?? 'error desconocido'}');
    } else if (res.status == 'image' || res.status == 'video') {
      showInfo(context, res.status == 'image' ? 'Foto del probador 3D guardada' : 'Video del probador 3D guardado');
    }
  }

  Future<void> _openTryOn() async {
    final chosen = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => TryOnScreen(product: p, initialSize: _size)),
    );
    if (chosen != null && mounted) setState(() => _size = chosen);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isBuyer = state.profile!.isBuyer;
    final body = state.body;
    final rec = recommendSize(body, state.profile!.size, p);
    final fav = state.favorites.contains(p.id);
    final details = body != null && _size != null && p.sizeChart[_size] != null
        ? fitDetails(body, p.sizeChart[_size]!, p.tryonType)
        : <ZoneFit>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(categoryLabels[p.category] ?? ''),
        actions: [
          if (isBuyer)
            IconButton(
              icon: Icon(fav ? Icons.favorite : Icons.favorite_border, color: fav ? AppColors.accent : null),
              onPressed: () => state.toggleFavorite(p.id),
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 120), children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: AspectRatio(
            aspectRatio: 1,
            child: Hero(tag: 'img-${p.id}-false', child: GarmentImage(p.imageUrl, padding: 28, radius: 24)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(p.brand.toUpperCase(),
                  style: const TextStyle(letterSpacing: 1, color: AppColors.muted, fontWeight: FontWeight.w600, fontSize: 12)),
              const Spacer(),
              if (_supplier != null)
                Pill(_supplier!.displayName,
                    icon: _supplier!.verified ? Icons.verified : Icons.storefront,
                    color: _supplier!.verified ? AppColors.chain : AppColors.muted),
            ]),
            const SizedBox(height: 4),
            Text(p.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.15)),
            const SizedBox(height: 6),
            Text(money.format(p.price), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.accent)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final s in p.styleTags) Pill(s)]),
          ]),
        ),
        const SectionTitle('Talla'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in p.sizes)
                ChoiceChip(
                  label: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(s),
                    if (rec?.size == s) ...[const SizedBox(width: 4), const Icon(Icons.auto_awesome, size: 14, color: AppColors.ai)],
                  ]),
                  selected: _size == s,
                  onSelected: (p.stock[s] ?? 0) > 0 ? (_) => setState(() => _size = s) : null,
                ),
            ]),
            if (rec != null && body != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.ai.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.auto_awesome, color: AppColors.ai, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Según tus medidas te recomendamos la talla ${rec.size}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  for (final d in details)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 26),
                      child: Text(
                        '${zoneNames[d.zone]![0].toUpperCase()}${zoneNames[d.zone]!.substring(1)} en talla $_size: '
                        '${fitLabels[d.label]!.toLowerCase()} (${d.ease >= 0 ? '+' : ''}${d.ease.round()} cm)',
                        style: const TextStyle(fontSize: 13, color: AppColors.muted),
                      ),
                    ),
                ]),
              ),
            ],
            if (_size != null && (p.stock[_size] ?? 0) <= 3 && (p.stock[_size] ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('¡Últimas ${p.stock[_size]} unidades en talla $_size!',
                    style: const TextStyle(color: AppColors.accent, fontSize: 13)),
              ),
          ]),
        ),
        const SectionTitle('Autenticidad y procedencia'),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: AuthenticityCard(product: p)),
        const SectionTitle('Descripción'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.description, style: const TextStyle(height: 1.45)),
            const SizedBox(height: 12),
            _kv('Materiales', p.materials),
            _kv('Origen', p.origin),
            _kv('Color', p.color),
          ]),
        ),
        if (p.sizeChart.isNotEmpty) ...[
          const SectionTitle('Tabla de medidas (cm)'),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _SizeTable(product: p)),
        ],
        if (!isBuyer) ...[
          const SectionTitle('Etiqueta QR para la prenda física', subtitle: 'Imprímela y cósela a la prenda: cualquiera puede escanearla para verificarla'),
          Center(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: QrImageView(data: 'arfit://product/${p.id}', size: 180),
            ),
          ),
        ],
      ]),
      bottomNavigationBar: isBuyer
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: [
                  if (_snapReady) ...[
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.ar),
                        onPressed: _openTryOn3D,
                        icon: const Icon(Icons.view_in_ar_rounded),
                        label: const Text('Probar en 3D'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      tooltip: 'Probador rápido',
                      style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
                      onPressed: _openTryOn,
                      icon: const Icon(Icons.accessibility_new),
                    ),
                  ] else
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.ar),
                        onPressed: _openTryOn,
                        icon: const Icon(Icons.view_in_ar_rounded),
                        label: const Text('Probar en RA'),
                      ),
                    ),
                  const SizedBox(width: 10),
                  Expanded(child: BusyButton(label: 'Al carrito', icon: Icons.add_shopping_cart, onPressed: p.sizesInStock.isEmpty ? null : _addToCart)),
                ]),
              ),
            )
          : null,
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 92, child: Text(k, style: const TextStyle(color: AppColors.muted))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w500))),
        ]),
      );
}

class _SizeTable extends StatelessWidget {
  const _SizeTable({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final cols = <String>[];
    for (final m in product.sizeChart.values) {
      if (m.chest != null && !cols.contains('chest')) cols.add('chest');
      if (m.waist != null && !cols.contains('waist')) cols.add('waist');
      if (m.hip != null && !cols.contains('hip')) cols.add('hip');
      if (m.length != null && !cols.contains('length')) cols.add('length');
    }
    const names = {'chest': 'Pecho', 'waist': 'Cintura', 'hip': 'Cadera', 'length': 'Largo'};
    String cell(SizeMeasures m, String c) {
      final v = switch (c) { 'chest' => m.chest, 'waist' => m.waist, 'hip' => m.hip, _ => m.length };
      return v == null ? '—' : v.round().toString();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Table(children: [
          TableRow(children: [
            const Text('Talla', style: TextStyle(fontWeight: FontWeight.w700)),
            for (final c in cols) Text(names[c]!, style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          for (final s in product.sizes)
            TableRow(children: [
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(s)),
              for (final c in cols) Padding(padding: const EdgeInsets.only(top: 8), child: Text(cell(product.sizeChart[s]!, c))),
            ]),
        ]),
      ),
    );
  }
}
