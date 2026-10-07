import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/labels.dart';
import '../../core/models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Panel del administrador: verificación de proveedores y de prendas on-chain.
class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  List<Profile>? _profiles;
  List<Product>? _products;
  List<Order>? _orders;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Future.wait([Api.allProfiles(), Api.products(), Api.orders(asRole: 'admin')]);
    if (!mounted) return;
    setState(() {
      _profiles = r[0] as List<Profile>;
      _products = r[1] as List<Product>;
      _orders = r[2] as List<Order>;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profiles = _profiles, products = _products, orders = _orders;
    if (profiles == null || products == null || orders == null) {
      return Scaffold(appBar: AppBar(title: const Text('Panel')), body: const Center(child: CircularProgressIndicator()));
    }
    final byRole = <String, int>{};
    for (final p in profiles) {
      byRole[p.role] = (byRole[p.role] ?? 0) + 1;
    }
    final partners = profiles.where((p) => p.isSupplier || p.isCarrier).toList();
    final pending = products.where((p) => !p.chainVerified).toList();
    final sales = orders.where((o) => o.status != 'cancelled').fold<double>(0, (a, b) => a + b.total);

    return Scaffold(
      appBar: AppBar(title: const Text('Panel de administración')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2,
            children: [
              _stat('Compradores', '${byRole['comprador'] ?? 0}', Icons.people_outline, AppColors.ar),
              _stat('Proveedores', '${byRole['proveedor'] ?? 0}', Icons.storefront_outlined, AppColors.accent),
              _stat('Prendas on-chain', '${products.where((p) => p.chainProductId != null).length}/${products.length}', Icons.link, AppColors.chain),
              _stat('Ventas', money.format(sales), Icons.payments_outlined, AppColors.ai),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: openExplorerContract, icon: const Icon(Icons.open_in_new), label: const Text('Contrato en PolygonScan')),
          const SectionTitle('Proveedores y transportistas'),
          for (final p in partners)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: SwitchListTile(
                value: p.verified,
                title: Text(p.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${roleLabels[p.role]} · ${p.city ?? 'sin ciudad'}'),
                secondary: Icon(p.isSupplier ? Icons.storefront : Icons.local_shipping, color: p.verified ? AppColors.chain : AppColors.muted),
                onChanged: (v) async {
                  await Api.setVerified(p.id, v);
                  _load();
                },
              ),
            ),
          SectionTitle('Prendas por verificar', subtitle: '${pending.length} pendientes · la verificación se firma en blockchain'),
          if (pending.isEmpty)
            const Padding(padding: EdgeInsets.all(12), child: Text('Todas las prendas están verificadas ✓'))
          else
            for (final p in pending)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(children: [
                    SizedBox(width: 50, height: 56, child: GarmentImage(p.imageUrl, padding: 4, radius: 10)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${p.origin} · ${p.materials}', maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 116,
                      child: BusyButton(
                        label: p.chainProductId == null ? 'Registrar' : 'Verificar',
                        color: AppColors.chain,
                        onPressed: () async {
                          if (p.chainProductId == null) await Api.registerOnChain(p.id);
                          final res = await Api.verifyProductOnChain(p.id, true);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('${p.name} verificada en blockchain'),
                            action: SnackBarAction(label: 'Ver tx', onPressed: () => openExplorerTx(res['tx_hash'])),
                          ));
                          _load();
                        },
                      ),
                    ),
                  ]),
                ),
              ),
        ]),
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon, Color color) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                FittedBox(child: Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ]),
            ),
          ]),
        ),
      );
}
