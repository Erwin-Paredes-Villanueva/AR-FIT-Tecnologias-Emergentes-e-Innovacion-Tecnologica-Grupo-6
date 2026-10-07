import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'core/app_state.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_shell.dart';
import 'features/onboarding/measurements_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_PE');
  await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseKey);
  runApp(ChangeNotifierProvider(create: (_) => AppState(), child: const ArFitApp()));
}

class ArFitApp extends StatelessWidget {
  const ArFitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AR-FIT',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: const Locale('es', 'PE'),
      supportedLocales: const [Locale('es', 'PE'), Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const RootGate(),
    );
  }
}

/// Decide qué mostrar según la sesión y si el usuario completó su perfil.
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.signedIn) return const LoginScreen();
    final profile = state.profile;
    if (profile == null) {
      if (state.loadingProfile) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('No se pudo cargar tu perfil'),
            const SizedBox(height: 12),
            FilledButton(onPressed: state.loadProfile, child: const Text('Reintentar')),
            TextButton(onPressed: state.signOut, child: const Text('Cerrar sesión')),
          ]),
        ),
      );
    }
    if (!profile.onboarded) return const MeasurementsScreen(initialSetup: true);
    return const HomeShell();
  }
}
