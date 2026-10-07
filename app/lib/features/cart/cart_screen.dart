import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/labels.dart';
import '../../core/models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'checkout_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  List<CartItem>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await Api.cart();
    if (mounted) setState(() => _items = items);
  }

  Future<void> _setQty(CartItem item, int q) async {
    final state = context.read<AppState>();
    await Api.setCartQuantity(item.id, q);
    await _load();
    await state.refreshCart();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final total = items?.fold<double>(0, (a, b) => a + b.subtotal) ?? 0;
    final suppliers = items?.map((i) => i.product.supplierId).toSet().length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Carrito')),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const EmptyState(icon: Icons.shopping_bag_outlined, title: 'Tu carrito está vacío', message: 'Pruébate algo en RA y agrégalo aquí')
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final it = items[i];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(children: [
                          SizedBox(width: 80, height: 90, child: GarmentImage(it.product.imageUrl, padding: 8, radius: 12)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(it.product.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text('Talla ${it.size} · ${it.product.brand}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                              const SizedBox(height: 4),
                              Text(money.format(it.subtotal), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.accent)),
                            ]),
                          ),
                          Column(children: [
                            IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => _setQty(it, it.quantity + 1)),
                            Text('${it.quantity}', style: const TextStyle(fontWeight: FontWeight.w700)),
                            IconButton(
                              icon: Icon(it.quantity == 1 ? Icons.delete_outline : Icons.remove_circle_outline),
                              onPressed: () => _setQty(it, it.quantity - 1),
                            ),
                          ]),
                        ]),
                      ),
                    );
                  },
                ),
      bottomNavigationBar: items == null || items.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    const Text('Total', style: TextStyle(fontSize: 16)),
                    const Spacer(),
                    Text(money.format(total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ]),
                  if (suppliers > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Se generarán $suppliers pedidos (uno por proveedor), cada uno con su trazabilidad.',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                    ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => CheckoutScreen(total: total))),
                      child: const Text('Continuar al pago'),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }
}
