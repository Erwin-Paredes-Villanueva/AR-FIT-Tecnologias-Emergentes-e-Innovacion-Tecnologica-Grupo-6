import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/labels.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../orders/order_detail.dart';

/// Checkout con pago SIMULADO. El pedido y su trazabilidad sí se registran en
/// Polygon Amoy (blockchain real).
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.total});
  final double total;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: context.read<AppState>().profile!.fullName);
  late final _address = TextEditingController(text: context.read<AppState>().profile!.address ?? '');
  String? _city = 'Lima';
  String _payment = 'tarjeta';

  static const _methods = [
    ('tarjeta', Icons.credit_card, 'Tarjeta (simulada)'),
    ('yape', Icons.qr_code_2, 'Yape / Plin (simulado)'),
    ('contraentrega', Icons.payments_outlined, 'Pago contra entrega'),
  ];

  Future<void> _pay() async {
    if (!_form.currentState!.validate()) return;
    final state = context.read<AppState>();
    final orders = await Api.checkout(
      name: _name.text.trim(),
      address: _address.text.trim(),
      city: _city!,
      paymentMethod: _payment,
    );
    await state.refreshCart();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: AppColors.chain, size: 48),
        title: const Text('¡Pago aprobado!'),
        content: Text(
          '${orders.length == 1 ? 'Tu pedido se está' : 'Tus ${orders.length} pedidos se están'} registrando en la blockchain de Polygon. '
          'Podrás seguir cada etapa del envío con su transacción verificable.',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Ver pedido'))],
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => OrderDetail(orderId: orders.first)),
      (r) => r.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pago')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
          const Text('Datos de envío', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 10),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nombre de quien recibe'),
            validator: (v) => v != null && v.trim().length > 2 ? null : 'Requerido',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'Dirección'),
            validator: (v) => v != null && v.trim().length > 4 ? null : 'Requerido',
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _city,
            decoration: const InputDecoration(labelText: 'Ciudad'),
            items: [for (final c in peruCities) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => setState(() => _city = v),
          ),
          const SizedBox(height: 22),
          const Text('Método de pago', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 10),
          RadioGroup<String>(
            groupValue: _payment,
            onChanged: (v) => setState(() => _payment = v!),
            child: Column(children: [
              for (final (value, icon, label) in _methods)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: RadioListTile<String>(
                    value: value,
                    title: Text(label),
                    secondary: Icon(icon),
                  ),
                ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: const Row(children: [
              Icon(Icons.info_outline, color: Colors.amber),
              SizedBox(width: 10),
              Expanded(
                child: Text('Entorno académico: el pago es simulado y no se solicita ningún dato de tarjeta.',
                    style: TextStyle(fontSize: 13)),
              ),
            ]),
          ),
          const SizedBox(height: 22),
          Row(children: [
            const Text('Total a pagar', style: TextStyle(fontSize: 16)),
            const Spacer(),
            Text(money.format(widget.total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 14),
          BusyButton(label: 'Pagar ${money.format(widget.total)}', icon: Icons.lock_outline, onPressed: _pay),
        ]),
      ),
    );
  }
}
