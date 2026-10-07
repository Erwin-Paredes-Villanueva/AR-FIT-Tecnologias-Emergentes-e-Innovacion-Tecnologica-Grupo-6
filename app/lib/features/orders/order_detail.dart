import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/chain_reader.dart';
import '../../core/labels.dart';
import '../../core/models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'orders_screen.dart';

/// Detalle del pedido con su trazabilidad on-chain y las acciones de cada rol.
class OrderDetail extends StatefulWidget {
  const OrderDetail({super.key, required this.orderId});
  final String orderId;

  @override
  State<OrderDetail> createState() => _OrderDetailState();
}

class _OrderDetailState extends State<OrderDetail> {
  Order? _order;
  RealtimeChannel? _channel;
  Future<ChainOrder>? _chainCheck;

  @override
  void initState() {
    super.initState();
    _load();
    _channel = sb
        .channel('order-${widget.orderId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'shipment_events',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'order_id', value: widget.orderId),
          callback: (_) => _load(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: widget.orderId),
          callback: (_) => _load(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) sb.removeChannel(_channel!);
    super.dispose();
  }

  Future<void> _load() async {
    final o = await Api.order(widget.orderId);
    if (mounted) setState(() => _order = o);
  }

  Future<void> _event(String status, {String? carrierId, String? location, String? note}) async {
    final res = await Api.orderEvent(
      orderId: widget.orderId,
      status: status,
      location: location,
      note: note,
      carrierId: carrierId,
    );
    await _load();
    if (!mounted) return;
    final tx = (res['event'] as Map?)?['tx_hash'] as String?;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Registrado en Polygon: ${statusLabels[status]}'),
      action: tx == null ? null : SnackBarAction(label: 'Ver tx', onPressed: () => openExplorerTx(tx)),
    ));
  }

  /// Pide ubicación (y transportista si corresponde) antes de registrar el evento.
  Future<void> _askAndSend(String status, {bool pickCarrier = false}) async {
    final profile = context.read<AppState>().profile!;
    String? city = profile.city ?? _order!.shippingCity;
    String? carrierId;
    final note = TextEditingController();
    List<PublicProfile> carriers = [];
    if (pickCarrier) {
      carriers = await Api.publicProfiles(role: 'transportista');
      if (carriers.isEmpty) throw Exception('No hay transportistas registrados');
      carrierId = carriers.first.id;
    }
    if (!mounted) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(statusLabels[status]!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Este evento quedará registrado de forma inmutable en Polygon.',
                style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
            if (pickCarrier) ...[
              DropdownButtonFormField<String>(
                initialValue: carrierId,
                decoration: const InputDecoration(labelText: 'Transportista asignado'),
                items: [
                  for (final c in carriers)
                    DropdownMenuItem(value: c.id, child: Text('${c.displayName}${c.city != null ? ' · ${c.city}' : ''}')),
                ],
                onChanged: (v) => setSheet(() => carrierId = v),
              ),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<String>(
              initialValue: peruCities.contains(city) ? city : null,
              decoration: const InputDecoration(labelText: 'Ubicación'),
              items: [for (final c in peruCities) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setSheet(() => city = v),
            ),
            const SizedBox(height: 12),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Nota (opcional)')),
            const SizedBox(height: 18),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Registrar en blockchain')),
          ]),
        ),
      ),
    );
    if (ok != true) return;
    await _event(status, carrierId: carrierId, location: city, note: note.text.trim().isEmpty ? null : note.text.trim());
  }

  List<Widget> _actions(Order o, Profile me) {
    final isAdmin = me.isAdmin;
    final list = <Widget>[];
    void add(String label, IconData icon, Future<void> Function() fn, {bool outlined = false, Color? color}) =>
        list.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(width: double.infinity, child: BusyButton(label: label, icon: icon, onPressed: fn, outlined: outlined, color: color)),
        ));

    final supplier = isAdmin || me.id == o.supplierId;
    final carrier = isAdmin || me.id == o.carrierId;
    final buyer = isAdmin || me.id == o.buyerId;
    switch (o.status) {
      case 'created':
        if (supplier) add('Marcar como preparado', Icons.inventory_2_outlined, () => _askAndSend('prepared', pickCarrier: true));
      case 'prepared':
        if (carrier) add('Confirmar recojo del paquete', Icons.local_shipping_outlined, () => _askAndSend('picked_up'));
      case 'picked_up':
        if (carrier) add('Registrar en tránsito', Icons.route_outlined, () => _askAndSend('in_transit'));
      case 'in_transit':
        if (carrier) {
          add('Nuevo punto de control', Icons.add_location_alt_outlined, () => _askAndSend('in_transit'), outlined: true);
          add('Marcar como entregado', Icons.where_to_vote_outlined, () => _askAndSend('delivered'), color: AppColors.chain);
        }
      case 'delivered':
        if (buyer) add('Confirmar que recibí mi pedido', Icons.check_circle_outline, () => _event('received', location: o.shippingCity), color: AppColors.chain);
    }
    if ((o.status == 'created' || o.status == 'prepared') && (buyer || supplier)) {
      add('Cancelar pedido', Icons.cancel_outlined, () async {
        final sure = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('¿Cancelar pedido?'),
            content: const Text('La cancelación también quedará registrada en blockchain.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, cancelar')),
            ],
          ),
        );
        if (sure == true) await _event('cancelled');
      }, outlined: true);
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    final me = context.watch<AppState>().profile!;
    return Scaffold(
      appBar: AppBar(title: Text(o == null ? 'Pedido' : 'Pedido #${o.id.substring(0, 8).toUpperCase()}')),
      body: o == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Pill(statusLabels[o.status] ?? o.status, color: statusColor(o.status), filled: true),
                        const Spacer(),
                        Text(money.format(o.total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      ]),
                      const SizedBox(height: 12),
                      for (final it in o.items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            SizedBox(width: 44, height: 50, child: GarmentImage(it.imageUrl, padding: 4, radius: 8)),
                            const SizedBox(width: 10),
                            Expanded(child: Text('${it.productName}\nTalla ${it.size} × ${it.quantity}')),
                            Text(money.format(it.unitPrice * it.quantity)),
                          ]),
                        ),
                      const Divider(),
                      Text('Envío a ${o.shippingName}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('${o.shippingAddress}, ${o.shippingCity}', style: const TextStyle(color: AppColors.muted)),
                      Text('Pago: ${o.paymentRef}', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                ..._actions(o, me),
                _ChainBanner(order: o),
                const SizedBox(height: 18),
                const Text('Trazabilidad del envío', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                for (var i = 0; i < o.events.length; i++)
                  _TimelineTile(event: o.events[i], last: i == o.events.length - 1),
                if (o.chainStatus == 'confirmed') ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _chainCheck = ChainReader().getOrder(o.id)),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Auditar historial en blockchain'),
                  ),
                  if (_chainCheck != null) _ChainAudit(future: _chainCheck!, order: o),
                ],
              ]),
            ),
    );
  }
}

class _ChainBanner extends StatelessWidget {
  const _ChainBanner({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final (icon, color, text) = switch (order.chainStatus) {
      'confirmed' => (Icons.link, AppColors.chain, 'Pedido anclado en Polygon Amoy'),
      'failed' => (Icons.link_off, Colors.red.shade600, 'El registro on-chain falló; se reintentará en el próximo evento'),
      _ => (Icons.hourglass_top, Colors.orange.shade700, 'Registrando el pedido en blockchain…'),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        order.chainStatus == 'pending'
            ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: color))
            : Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
        TextButton(onPressed: openExplorerContract, child: const Text('Contrato')),
      ]),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.event, required this.last});
  final ShipmentEvent event;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(event.status);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 28,
          child: Column(children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
            ),
            if (!last) Expanded(child: Container(width: 2, color: const Color(0xFFDDD6CC))),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(statusLabels[event.status] ?? event.status, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                '${dateTimeFmt.format(event.createdAt.toLocal())}'
                '${event.location.isNotEmpty ? ' · ${event.location}' : ''} · ${roleLabels[event.actorRole] ?? event.actorRole}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
              if (event.note.isNotEmpty) Text(event.note, style: const TextStyle(fontSize: 13.5)),
              const SizedBox(height: 4),
              if (event.txHash != null)
                InkWell(
                  onTap: () => openExplorerTx(event.txHash!),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.link, size: 15, color: AppColors.chain),
                    const SizedBox(width: 4),
                    Text(
                      'tx ${shortHash(event.txHash!)}${event.blockNumber != null ? ' · bloque ${event.blockNumber}' : ''}',
                      style: const TextStyle(color: AppColors.chain, fontSize: 12.5, fontFamily: 'monospace'),
                    ),
                  ]),
                )
              else
                const Text('Sin transacción on-chain', style: TextStyle(color: Colors.orange, fontSize: 12.5)),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Compara el historial guardado en la base de datos con el de la blockchain.
class _ChainAudit extends StatelessWidget {
  const _ChainAudit({required this.future, required this.order});
  final Future<ChainOrder> future;
  final Order order;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ChainOrder>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) return Padding(padding: const EdgeInsets.all(12), child: Text('Error: ${snap.error}'));
        final c = snap.data!;
        final dbStatuses = order.events.where((e) => e.txHash != null).map((e) => e.status).toList();
        final chainStatusesList = c.events.map((e) => e.status).toList();
        final match = c.exists && c.status == order.status && dbStatuses.join(',') == chainStatusesList.join(',');
        final color = match ? AppColors.chain : Colors.red.shade600;
        return Card(
          margin: const EdgeInsets.only(top: 12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(match ? Icons.verified : Icons.warning_amber, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    match ? 'El historial coincide con la blockchain' : 'Hay diferencias con la blockchain',
                    style: TextStyle(fontWeight: FontWeight.w700, color: color),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Text('Estado on-chain: ${statusLabels[c.status]} · ${c.events.length} eventos · ${c.productCount} prenda(s)',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 6),
              for (final e in c.events)
                Text('• ${dateTimeFmt.format(e.timestamp)} — ${statusLabels[e.status]} (${e.actorRole}${e.location.isNotEmpty ? ', ${e.location}' : ''})',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
            ]),
          ),
        );
      },
    );
  }
}
