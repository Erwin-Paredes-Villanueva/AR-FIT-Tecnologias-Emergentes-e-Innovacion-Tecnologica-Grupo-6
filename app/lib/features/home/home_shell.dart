import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../admin/admin_home.dart';
import '../assistant/assistant_screen.dart';
import '../carrier/carrier_home.dart';
import '../orders/orders_screen.dart';
import '../profile/profile_screen.dart';
import '../supplier/supplier_home.dart';
import '../verify/verify_screen.dart';
import 'buyer_home.dart';

typedef _Tab = ({IconData icon, IconData selected, String label, Widget page});

/// Navegación inferior distinta para cada rol.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  List<_Tab> _tabs(String role) {
    const verify = (icon: Icons.qr_code_scanner, selected: Icons.qr_code_scanner, label: 'Verificar', page: VerifyScreen());
    const profile = (icon: Icons.person_outline, selected: Icons.person, label: 'Perfil', page: ProfileScreen());
    return switch (role) {
      'proveedor' => [
          (icon: Icons.checkroom_outlined, selected: Icons.checkroom, label: 'Mis prendas', page: const SupplierHome()),
          (icon: Icons.receipt_long_outlined, selected: Icons.receipt_long, label: 'Pedidos', page: const OrdersScreen(role: 'proveedor')),
          verify,
          profile,
        ],
      'transportista' => [
          (icon: Icons.local_shipping_outlined, selected: Icons.local_shipping, label: 'Envíos', page: const CarrierHome()),
          verify,
          profile,
        ],
      'admin' => [
          (icon: Icons.dashboard_outlined, selected: Icons.dashboard, label: 'Panel', page: const AdminHome()),
          (icon: Icons.receipt_long_outlined, selected: Icons.receipt_long, label: 'Pedidos', page: const OrdersScreen(role: 'admin')),
          verify,
          profile,
        ],
      _ => [
          (icon: Icons.home_outlined, selected: Icons.home, label: 'Para ti', page: const BuyerHome()),
          (icon: Icons.auto_awesome_outlined, selected: Icons.auto_awesome, label: 'Asistente', page: const AssistantScreen()),
          verify,
          (icon: Icons.receipt_long_outlined, selected: Icons.receipt_long, label: 'Pedidos', page: const OrdersScreen(role: 'comprador')),
          profile,
        ],
    };
  }

  @override
  Widget build(BuildContext context) {
    final role = context.select<AppState, String>((s) => s.profile!.role);
    final tabs = _tabs(role);
    if (_index >= tabs.length) _index = 0;
    return Scaffold(
      body: IndexedStack(index: _index, children: [for (final t in tabs) t.page]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final t in tabs) NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selected), label: t.label),
        ],
      ),
    );
  }
}
