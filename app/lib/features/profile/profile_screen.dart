import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../core/app_state.dart';
import '../../core/labels.dart';
import '../../core/models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../onboarding/measurements_screen.dart';
import '../onboarding/preferences_screen.dart';
import '../product/product_card.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = state.profile!;
    final body = state.body;
    final favs = state.catalog.where((x) => state.favorites.contains(x.id)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: AppColors.accent,
              child: Text(p.fullName.isEmpty ? '?' : p.fullName[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.fullName, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Row(children: [
                  Pill(roleLabels[p.role]!, color: AppColors.accent),
                  if (p.verified && !p.isBuyer) ...[
                    const SizedBox(width: 6),
                    const Pill('Verificado', icon: Icons.verified, color: AppColors.chain),
                  ],
                ]),
              ]),
            ),
          ]),
        ),
        if (p.isBuyer || p.isAdmin) ...[
          SectionTitle(
            'Mis medidas',
            trailing: TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MeasurementsScreen())),
              child: const Text('Editar'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: body == null
                    ? const Text('Registra tus medidas para usar el probador virtual')
                    : Column(children: [
                        Row(children: [
                          _m('Altura', '${body.height.round()} cm'),
                          _m('Peso', '${body.weight.round()} kg'),
                          _m('Talla', p.size ?? '—'),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          _m('Pecho', '${body.chest.round()}'),
                          _m('Cintura', '${body.waist.round()}'),
                          _m('Cadera', '${body.hip.round()}'),
                        ]),
                        if (body.estimated)
                          const Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: Text('Contornos estimados a partir de tu altura y peso',
                                style: TextStyle(color: AppColors.muted, fontSize: 12)),
                          ),
                      ]),
              ),
            ),
          ),
        ],
        if (p.isBuyer) ...[
          SectionTitle(
            'Tu perfil de estilo',
            subtitle: 'Lo que la IA aprendió de tus ${state.styleProfile?.signals ?? 0} interacciones',
            trailing: TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PreferencesScreen())),
              child: const Text('Ajustar'),
            ),
          ),
          if (state.styleProfile != null)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _StyleProfileCard(profile: state.styleProfile!)),
          if (favs.isNotEmpty) ...[
            const SectionTitle('Favoritos'),
            SizedBox(
              height: 260,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: favs.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, i) => SizedBox(width: 160, child: ProductCard(product: favs[i])),
              ),
            ),
          ],
        ],
        if (p.isSupplier || p.isCarrier) ...[
          SectionTitle(
            p.isSupplier ? 'Mi tienda' : 'Mi empresa',
            trailing: TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MeasurementsScreen())),
              child: const Text('Editar'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Card(
              child: Column(children: [
                if (p.storeName != null) ListTile(leading: const Icon(Icons.storefront_outlined), title: Text(p.storeName!)),
                ListTile(leading: const Icon(Icons.business_outlined), title: Text(p.companyName ?? '—')),
                ListTile(leading: const Icon(Icons.place_outlined), title: Text('${p.address ?? ''} ${p.city ?? ''}'.trim())),
              ]),
            ),
          ),
        ],
        const SectionTitle('Tecnología'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Card(
            child: Column(children: [
              const ListTile(
                leading: Icon(Icons.auto_awesome, color: AppColors.ai),
                title: Text('Inteligencia artificial'),
                subtitle: Text('Recomendador híbrido + asistente Google Gemini'),
              ),
              const ListTile(
                leading: Icon(Icons.view_in_ar_rounded, color: AppColors.ar),
                title: Text('Realidad aumentada'),
                subtitle: Text('Detección de pose ML Kit + ajuste por medidas'),
              ),
              ListTile(
                leading: const Icon(Icons.link, color: AppColors.chain),
                title: const Text('Blockchain · Polygon Amoy'),
                subtitle: Text(shortHash(AppConfig.contractAddress, 8), style: const TextStyle(fontFamily: 'monospace')),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: openExplorerContract,
              ),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: OutlinedButton.icon(
            onPressed: state.signOut,
            icon: const Icon(Icons.logout),
            label: const Text('Cerrar sesión'),
          ),
        ),
      ]),
    );
  }

  Widget _m(String label, String value) => Expanded(
        child: Column(children: [
          Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
      );
}

class _StyleProfileCard extends StatelessWidget {
  const _StyleProfileCard({required this.profile});
  final StyleProfile profile;

  @override
  Widget build(BuildContext context) {
    Widget bars(String title, List<WeightedKey> items, Color color, {String Function(String)? label}) {
      if (items.isEmpty) return const SizedBox();
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          for (final it in items.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(children: [
                SizedBox(width: 92, child: Text(label?.call(it.key) ?? it.key, style: const TextStyle(fontSize: 13))),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: it.weight,
                      minHeight: 8,
                      backgroundColor: color.withValues(alpha: 0.1),
                      color: color,
                    ),
                  ),
                ),
                SizedBox(width: 40, child: Text('${(it.weight * 100).round()}%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
              ]),
            ),
        ]),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          bars('Estilos', profile.styles, AppColors.ai),
          bars('Categorías', profile.categories, AppColors.accent, label: (k) => categoryLabels[k] ?? k),
          bars('Colores', profile.colors, AppColors.ar),
          bars('Marcas', profile.brands, AppColors.chain),
        ]),
      ),
    );
  }
}
