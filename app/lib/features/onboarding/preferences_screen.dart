import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/labels.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Preferencias declaradas: resuelven el "arranque en frío" del recomendador.
class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({super.key, this.initialSetup = false});
  final bool initialSetup;

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  late final p = context.read<AppState>().profile!;
  late final Set<String> _styles = {...p.stylePrefs};
  late final Set<String> _colors = {...p.colorPrefs};
  late final Set<String> _categories = {...p.categoryPrefs};

  Future<void> _save() async {
    if (_styles.isEmpty) throw Exception('Elige al menos un estilo');
    final state = context.read<AppState>();
    await Api.updateProfile({
      'style_prefs': _styles.toList(),
      'color_prefs': _colors.toList(),
      'category_prefs': _categories.toList(),
      'onboarded': true,
    });
    await state.loadProfile();
    if (!mounted) return;
    if (widget.initialSetup) {
      Navigator.popUntil(context, (r) => r.isFirst);
    } else {
      Navigator.pop(context);
      state.loadFeed();
    }
  }

  Widget _group(String title, List<String> options, Set<String> selected, {Map<String, int>? colors}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 10),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      ),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final o in options)
          FilterChip(
            avatar: colors == null
                ? null
                : CircleAvatar(backgroundColor: Color(colors[o]!), radius: 8),
            label: Text(categoryLabels[o] ?? o),
            selected: selected.contains(o),
            onSelected: (v) => setState(() => v ? selected.add(o) : selected.remove(o)),
          ),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tu estilo')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
        Row(children: const [
          Icon(Icons.auto_awesome, color: AppColors.ai, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'La IA parte de estas preferencias y luego aprende de lo que ves, te pruebas y compras.',
              style: TextStyle(color: AppColors.muted),
            ),
          ),
        ]),
        _group('Estilos que te gustan', styleOptions, _styles),
        _group('Colores favoritos', colorOptions.keys.toList(), _colors, colors: colorOptions),
        _group('¿Qué sueles comprar?', categoryLabels.keys.toList(), _categories),
        const SizedBox(height: 28),
        BusyButton(label: widget.initialSetup ? 'Empezar a explorar' : 'Guardar', onPressed: _save),
      ]),
    );
  }
}
