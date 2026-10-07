import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../orders/orders_screen.dart';

/// Envíos asignados al transportista, agrupados por etapa.
class CarrierHome extends StatefulWidget {
  const CarrierHome({super.key});

  @override
  State<CarrierHome> createState() => _CarrierHomeState();
}

class _CarrierHomeState extends State<CarrierHome> {
  List<Order>? _orders;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _channel = sb
        .channel('carrier-orders')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'orders', callback: (_) => _load())
        .subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) sb.removeChannel(_channel!);
    super.dispose();
  }

  Future<void> _load() async {
    final list = await Api.orders(asRole: 'transportista');
    if (mounted) setState(() => _orders = list);
  }

  Widget _list(List<Order> orders, String empty) => RefreshIndicator(
        onRefresh: _load,
        child: orders.isEmpty
            ? ListView(children: [const SizedBox(height: 60), EmptyState(icon: Icons.local_shipping_outlined, title: empty)])
            : ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: orders.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) => OrderTile(order: orders[i]),
              ),
      );

  @override
  Widget build(BuildContext context) {
    final o = _orders;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mis envíos'),
          bottom: const TabBar(
            indicatorColor: AppColors.accent,
            labelColor: AppColors.ink,
            tabs: [Tab(text: 'Por recoger'), Tab(text: 'En ruta'), Tab(text: 'Entregados')],
          ),
        ),
        body: o == null
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(children: [
                _list(o.where((x) => x.status == 'prepared').toList(), 'No tienes paquetes por recoger'),
                _list(o.where((x) => x.status == 'picked_up' || x.status == 'in_transit').toList(), 'No tienes paquetes en ruta'),
                _list(o.where((x) => x.status == 'delivered' || x.status == 'received').toList(), 'Aún no hay entregas'),
              ]),
      ),
    );
  }
}
