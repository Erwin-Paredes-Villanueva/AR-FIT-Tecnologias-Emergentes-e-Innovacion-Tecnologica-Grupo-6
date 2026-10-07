import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api.dart';
import '../../core/labels.dart';
import '../../core/models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'order_detail.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, required this.role, this.title});
  final String role;
  final String? title;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List<Order>? _orders;
  String? _error;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    // actualización en vivo cuando cambia un pedido o llega un evento on-chain
    _channel = sb
        .channel('orders-${widget.role}')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'orders', callback: (_) => _load())
        .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'shipment_events', callback: (_) => _load())
        .subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) sb.removeChannel(_channel!);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final orders = await Api.orders(asRole: widget.role);
      if (mounted) setState(() => (_orders = orders, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final orders = _orders;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? (widget.role == 'comprador' ? 'Mis pedidos' : 'Pedidos'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _error != null
            ? ListView(children: [EmptyState(icon: Icons.cloud_off, title: 'Error', message: _error)])
            : orders == null
                ? const Center(child: CircularProgressIndicator())
                : orders.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 80),
                        EmptyState(icon: Icons.receipt_long_outlined, title: 'Aún no hay pedidos'),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: orders.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => OrderTile(order: orders[i]),
                      ),
      ),
    );
  }
}

Color statusColor(String s) => switch (s) {
      'created' => AppColors.ar,
      'prepared' => AppColors.ai,
      'picked_up' || 'in_transit' => Colors.orange.shade700,
      'delivered' || 'received' => AppColors.chain,
      'cancelled' => Colors.red.shade600,
      _ => AppColors.muted,
    };

class OrderTile extends StatelessWidget {
  const OrderTile({super.key, required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final o = order;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetail(orderId: o.id))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            SizedBox(
              width: 64,
              height: 72,
              child: o.items.isEmpty ? const SizedBox() : GarmentImage(o.items.first.imageUrl, padding: 6, radius: 12),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Pedido #${o.id.substring(0, 8).toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  '${o.items.length} prenda${o.items.length == 1 ? '' : 's'} · ${money.format(o.total)} · ${o.shippingCity}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Pill(statusLabels[o.status] ?? o.status, color: statusColor(o.status)),
                  const SizedBox(width: 6),
                  if (o.chainStatus == 'confirmed')
                    const Icon(Icons.link, size: 16, color: AppColors.chain)
                  else if (o.chainStatus == 'pending')
                    const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
                ]),
              ]),
            ),
            const Icon(Icons.chevron_right, color: AppColors.muted),
          ]),
        ),
      ),
    );
  }
}
