import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/labels.dart';
import '../../core/models.dart';
import '../../core/sizing.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'preferences_screen.dart';

/// Registro de medidas (comprador) o datos del negocio (proveedor/transportista).
class MeasurementsScreen extends StatefulWidget {
  const MeasurementsScreen({super.key, this.initialSetup = false});
  final bool initialSetup;

  @override
  State<MeasurementsScreen> createState() => _MeasurementsScreenState();
}

class _MeasurementsScreenState extends State<MeasurementsScreen> {
  final _form = GlobalKey<FormState>();
  late final Profile p = context.read<AppState>().profile!;

  late String? _gender = p.gender;
  late String? _size = p.size;
  late final _height = TextEditingController(text: _fmt(p.heightCm));
  late final _weight = TextEditingController(text: _fmt(p.weightKg));
  late final _chest = TextEditingController(text: _fmt(p.chestCm));
  late final _waist = TextEditingController(text: _fmt(p.waistCm));
  late final _hip = TextEditingController(text: _fmt(p.hipCm));
  late final _shoulder = TextEditingController(text: _fmt(p.shoulderCm));
  late bool _knowsMeasures = p.chestCm != null;

  late final _store = TextEditingController(text: p.storeName ?? '');
  late final _company = TextEditingController(text: p.companyName ?? '');
  late final _address = TextEditingController(text: p.address ?? '');
  late final _phone = TextEditingController(text: p.phone ?? '');
  late String? _city = p.city;

  static String _fmt(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());
  double? _num(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.'));

  BodyMeasures? get _preview {
    final h = _num(_height), w = _num(_weight);
    if (h == null || w == null || h < 120 || w < 30) return null;
    return BodyMeasures.estimate(
      heightCm: h,
      weightKg: w,
      gender: _gender,
      chest: _knowsMeasures ? _num(_chest) : null,
      waist: _knowsMeasures ? _num(_waist) : null,
      hip: _knowsMeasures ? _num(_hip) : null,
      shoulder: _knowsMeasures ? _num(_shoulder) : null,
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final state = context.read<AppState>();
    final Map<String, dynamic> values;
    if (p.isBuyer || p.isAdmin) {
      values = {
        'gender': _gender,
        'height_cm': _num(_height),
        'weight_kg': _num(_weight),
        'size': _size,
        'chest_cm': _knowsMeasures ? _num(_chest) : null,
        'waist_cm': _knowsMeasures ? _num(_waist) : null,
        'hip_cm': _knowsMeasures ? _num(_hip) : null,
        'shoulder_cm': _knowsMeasures ? _num(_shoulder) : null,
      };
    } else {
      values = {
        'store_name': p.isSupplier ? _store.text.trim() : null,
        'company_name': _company.text.trim(),
        'city': _city,
        'address': _address.text.trim(),
        'phone': _phone.text.trim(),
      };
    }
    if (!widget.initialSetup || !p.isBuyer) values['onboarded'] = true;
    await Api.updateProfile(values);
    await state.loadProfile();
    if (!mounted) return;
    if (widget.initialSetup && p.isBuyer) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const PreferencesScreen(initialSetup: true)));
    } else if (!widget.initialSetup) {
      Navigator.pop(context);
      showInfo(context, 'Datos actualizados');
    }
  }

  String? _range(String? v, double min, double max, {bool required = true}) {
    if (v == null || v.isEmpty) return required ? 'Requerido' : null;
    final n = double.tryParse(v.replaceAll(',', '.'));
    if (n == null || n < min || n > max) return 'Entre ${min.toInt()} y ${max.toInt()}';
    return null;
  }

  Widget _numField(TextEditingController c, String label, String suffix, double min, double max, {bool required = true}) {
    return TextFormField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, suffixText: suffix),
      validator: (v) => _range(v, min, max, required: required),
      onChanged: (_) => setState(() {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final business = p.isSupplier || p.isCarrier;
    return Scaffold(
      appBar: AppBar(
        title: Text(business ? 'Datos de tu ${p.isSupplier ? 'tienda' : 'empresa'}' : 'Tus medidas'),
        automaticallyImplyLeading: !widget.initialSetup,
        actions: [
          if (widget.initialSetup) TextButton(onPressed: context.read<AppState>().signOut, child: const Text('Salir')),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: business ? _businessFields() : _bodyFields(),
        ),
      ),
    );
  }

  List<Widget> _businessFields() => [
        if (widget.initialSetup)
          Text(
            p.isSupplier
                ? 'Tus prendas se registrarán en blockchain con la procedencia que declares. Un administrador verificará tu tienda.'
                : 'Podrás registrar en blockchain cada etapa de los envíos que se te asignen.',
            style: const TextStyle(color: AppColors.muted, height: 1.4),
          ),
        const SizedBox(height: 16),
        if (p.isSupplier) ...[
          TextFormField(
            controller: _store,
            decoration: const InputDecoration(labelText: 'Nombre comercial de la tienda'),
            validator: (v) => v != null && v.trim().length >= 2 ? null : 'Requerido',
          ),
          const SizedBox(height: 12),
        ],
        TextFormField(
          controller: _company,
          decoration: InputDecoration(labelText: p.isSupplier ? 'Razón social' : 'Empresa de transporte'),
          validator: (v) => v != null && v.trim().length >= 2 ? null : 'Requerido',
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _city,
          decoration: const InputDecoration(labelText: 'Ciudad'),
          items: [for (final c in peruCities) DropdownMenuItem(value: c, child: Text(c))],
          onChanged: (v) => setState(() => _city = v),
          validator: (v) => v == null ? 'Requerido' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(controller: _address, decoration: const InputDecoration(labelText: 'Dirección')),
        const SizedBox(height: 12),
        TextFormField(
            controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono')),
        const SizedBox(height: 24),
        BusyButton(label: 'Guardar', onPressed: _save),
      ];

  List<Widget> _bodyFields() {
    final preview = _preview;
    return [
      if (widget.initialSetup)
        const Text(
          'Usamos tus medidas para que el probador de realidad aumentada muestre cómo te quedaría cada talla y para recomendarte la talla ideal.',
          style: TextStyle(color: AppColors.muted, height: 1.4),
        ),
      const SizedBox(height: 16),
      const Text('Sexo', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'mujer', label: Text('Mujer')),
          ButtonSegment(value: 'hombre', label: Text('Hombre')),
          ButtonSegment(value: 'otro', label: Text('Otro')),
        ],
        selected: {?_gender},
        emptySelectionAllowed: true,
        onSelectionChanged: (s) => setState(() => _gender = s.isEmpty ? null : s.first),
      ),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: _numField(_height, 'Altura', 'cm', 120, 230)),
        const SizedBox(width: 12),
        Expanded(child: _numField(_weight, 'Peso', 'kg', 30, 250)),
      ]),
      const SizedBox(height: 16),
      const Text('Talla que usas normalmente', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        for (final s in sizeOrder)
          ChoiceChip(label: Text(s), selected: _size == s, onSelected: (_) => setState(() => _size = s)),
      ]),
      const SizedBox(height: 16),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _knowsMeasures,
        onChanged: (v) => setState(() => _knowsMeasures = v),
        title: const Text('Conozco mis contornos'),
        subtitle: const Text('Si no, los estimamos a partir de tu altura y peso'),
      ),
      if (_knowsMeasures) ...[
        Row(children: [
          Expanded(child: _numField(_chest, 'Pecho', 'cm', 60, 170)),
          const SizedBox(width: 12),
          Expanded(child: _numField(_waist, 'Cintura', 'cm', 45, 170)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _numField(_hip, 'Cadera', 'cm', 60, 180)),
          const SizedBox(width: 12),
          Expanded(child: _numField(_shoulder, 'Hombros', 'cm', 28, 60, required: false)),
        ]),
      ],
      if (preview != null) ...[
        const SizedBox(height: 16),
        _BodyPreview(body: preview),
      ],
      const SizedBox(height: 24),
      BusyButton(
        label: widget.initialSetup ? 'Continuar' : 'Guardar medidas',
        onPressed: () async {
          if (_gender == null || _size == null) throw Exception('Selecciona tu sexo y talla habitual');
          await _save();
        },
      ),
    ];
  }
}

class _BodyPreview extends StatelessWidget {
  const _BodyPreview({required this.body});
  final BodyMeasures body;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, double v) => Expanded(
          child: Column(children: [
            Text('${v.round()}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.accessibility_new, color: AppColors.ai, size: 20),
            const SizedBox(width: 8),
            Text(body.estimated ? 'Contornos estimados (cm)' : 'Tus contornos (cm)',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Pill('Talla sugerida ${body.suggestedSize}', color: AppColors.ai),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            cell('Pecho', body.chest),
            cell('Cintura', body.waist),
            cell('Cadera', body.hip),
            cell('Hombros', body.shoulder),
          ]),
        ]),
      ),
    );
  }
}
