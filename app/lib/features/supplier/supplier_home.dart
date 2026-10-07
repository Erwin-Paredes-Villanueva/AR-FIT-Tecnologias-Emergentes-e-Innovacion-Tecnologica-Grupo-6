import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/labels.dart';
import '../../core/models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../product/product_detail.dart';
import 'product_form.dart';

class SupplierHome extends StatefulWidget {
  const SupplierHome({super.key});

  @override
  State<SupplierHome> createState() => _SupplierHomeState();
}

class _SupplierHomeState extends State<SupplierHome> {
  List<Product>? _products;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await Api.products(supplierId: sb.auth.currentUser!.id);
    if (mounted) setState(() => _products = list);
  }

  Future<void> _edit([Product? p]) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ProductForm(product: p)));
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AppState>().profile!;
    final products = _products;
    return Scaffold(
      appBar: AppBar(title: Text(profile.storeName ?? 'Mi tienda')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Nueva prenda'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 100), children: [
          if (!profile.verified)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
              child: const Row(children: [
                Icon(Icons.pending_outlined, color: Colors.orange),
                SizedBox(width: 10),
                Expanded(child: Text('Tu tienda está pendiente de verificación por un administrador.')),
              ]),
            ),
          if (products != null)
            Row(children: [
              _stat('Prendas', '${products.length}'),
              _stat('En blockchain', '${products.where((p) => p.chainProductId != null).length}'),
              _stat('Stock total', '${products.fold<int>(0, (a, b) => a + b.totalStock)}'),
            ]),
          const SizedBox(height: 14),
          if (products == null)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else if (products.isEmpty)
            const EmptyState(icon: Icons.checkroom, title: 'Aún no publicas prendas', message: 'Agrega tu primera prenda y regístrala en blockchain')
          else
            for (final p in products)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(10),
                  leading: SizedBox(width: 56, height: 64, child: GarmentImage(p.imageUrl, padding: 4, radius: 10)),
                  title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(spacing: 6, runSpacing: 4, children: [
                      Text('${money.format(p.price)} · stock ${p.totalStock}'),
                      if (p.chainVerified)
                        const Pill('Verificada', icon: Icons.verified, color: AppColors.chain)
                      else if (p.chainProductId != null)
                        const Pill('En blockchain', icon: Icons.link, color: AppColors.chain)
                      else
                        const Pill('Sin registrar', icon: Icons.link_off, color: Colors.orange),
                      if (!p.active) const Pill('Oculta', color: AppColors.muted),
                    ]),
                  ),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetail(product: p))),
                  trailing: IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(p)),
                ),
              ),
        ]),
      ),
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Card(
          margin: const EdgeInsets.only(right: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
          ),
        ),
      );
}
