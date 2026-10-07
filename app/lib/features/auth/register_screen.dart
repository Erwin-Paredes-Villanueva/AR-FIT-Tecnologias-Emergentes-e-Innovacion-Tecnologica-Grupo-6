import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String _role = 'comprador';

  static const _roles = [
    ('comprador', Icons.shopping_bag_outlined, 'Comprador', 'Descubre, pruébate en RA y compra prendas'),
    ('proveedor', Icons.storefront_outlined, 'Proveedor', 'Vende tus prendas con procedencia certificada'),
    ('transportista', Icons.local_shipping_outlined, 'Transportista', 'Registra cada etapa del envío en blockchain'),
  ];

  Future<void> _register() async {
    if (!_form.currentState!.validate()) return;
    try {
      final res = await sb.auth.signUp(
        email: _email.text.trim(),
        password: _password.text,
        data: {'full_name': _name.text.trim(), 'role': _role},
      );
      if (!mounted) return;
      if (res.session == null) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Confirma tu correo'),
            content: Text('Te enviamos un enlace a ${_email.text.trim()}. Confírmalo y luego inicia sesión.'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
          ),
        );
      }
      if (mounted) Navigator.pop(context);
    } on AuthException catch (e) {
      throw Exception(e.message.contains('already registered') ? 'Ese correo ya está registrado' : e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
          const Text('¿Cómo usarás AR-FIT?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 10),
          for (final (value, icon, title, desc) in _roles)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => setState(() => _role = value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _role == value ? AppColors.accent : const Color(0xFFE6E1DA), width: _role == value ? 2 : 1),
                  ),
                  child: Row(children: [
                    Icon(icon, color: _role == value ? AppColors.accent : AppColors.ink),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(desc, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                      ]),
                    ),
                    if (_role == value) const Icon(Icons.check_circle, color: AppColors.accent),
                  ]),
                ),
              ),
            ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nombre completo', prefixIcon: Icon(Icons.person_outline)),
            validator: (v) => v != null && v.trim().length >= 3 ? null : 'Ingresa tu nombre',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Correo electrónico', prefixIcon: Icon(Icons.mail_outline)),
            validator: (v) => v != null && RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()) ? null : 'Correo no válido',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Contraseña', prefixIcon: Icon(Icons.lock_outline)),
            validator: (v) => v != null && v.length >= 6 ? null : 'Mínimo 6 caracteres',
          ),
          const SizedBox(height: 22),
          BusyButton(label: 'Registrarme', onPressed: _register),
          const SizedBox(height: 10),
          const Text(
            'Tras registrarte te pediremos tus medidas para que el probador virtual y las tallas sugeridas sean precisos.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
        ]),
      ),
    );
  }
}
