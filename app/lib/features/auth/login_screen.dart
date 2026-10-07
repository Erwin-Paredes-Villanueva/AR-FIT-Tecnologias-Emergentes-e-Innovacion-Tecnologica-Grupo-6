import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _obscure = true;

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    try {
      await sb.auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
    } on AuthException catch (e) {
      throw Exception(e.message == 'Invalid login credentials' ? 'Correo o contraseña incorrectos' : e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Center(child: Logo(size: 34)),
                const SizedBox(height: 14),
                const Text(
                  'Moda phygital: pruébate la ropa con realidad aumentada, recibe recomendaciones con IA y verifica cada prenda en blockchain.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, height: 1.4),
                ),
                const SizedBox(height: 26),
                const _TechRow(),
                const SizedBox(height: 30),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Correo electrónico', prefixIcon: Icon(Icons.mail_outline)),
                  validator: (v) => v != null && v.contains('@') ? null : 'Correo no válido',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => v != null && v.length >= 6 ? null : 'Mínimo 6 caracteres',
                ),
                const SizedBox(height: 20),
                BusyButton(label: 'Iniciar sesión', onPressed: _login),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
                  child: const Text('Crear una cuenta'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _TechRow extends StatelessWidget {
  const _TechRow();

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String label, Color color) => Expanded(
          child: Column(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        );
    return Row(children: [
      item(Icons.auto_awesome, 'IA', AppColors.ai),
      item(Icons.view_in_ar_rounded, 'Probador RA', AppColors.ar),
      item(Icons.link_rounded, 'Blockchain', AppColors.chain),
    ]);
  }
}
