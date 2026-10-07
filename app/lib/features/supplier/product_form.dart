import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/background_removal.dart';
import '../../core/labels.dart';
import '../../core/models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Tablas de tallas por defecto (cm) según la categoría.
const _defaultCharts = <String, Map<String, Map<String, double>>>{
  'polo': {
    'S': {'chest': 96, 'length': 68}, 'M': {'chest': 102, 'length': 70},
    'L': {'chest': 108, 'length': 72}, 'XL': {'chest': 114, 'length': 74},
  },
  'camisa': {
    'S': {'chest': 100, 'length': 72}, 'M': {'chest': 106, 'length': 74},
    'L': {'chest': 112, 'length': 76}, 'XL': {'chest': 118, 'length': 78},
  },
  'polera': {
    'S': {'chest': 104, 'length': 66}, 'M': {'chest': 110, 'length': 68},
    'L': {'chest': 116, 'length': 70}, 'XL': {'chest': 122, 'length': 72},
  },
  'casaca': {
    'S': {'chest': 104, 'length': 64}, 'M': {'chest': 110, 'length': 66},
    'L': {'chest': 116, 'length': 68}, 'XL': {'chest': 122, 'length': 70},
  },
  'vestido': {
    'XS': {'chest': 82, 'waist': 64, 'hip': 90, 'length': 95}, 'S': {'chest': 86, 'waist': 68, 'hip': 94, 'length': 97},
    'M': {'chest': 90, 'waist': 72, 'hip': 98, 'length': 99}, 'L': {'chest': 96, 'waist': 78, 'hip': 104, 'length': 101},
  },
  'pantalon': {
    'S': {'waist': 74, 'hip': 96, 'length': 100}, 'M': {'waist': 80, 'hip': 102, 'length': 102},
    'L': {'waist': 86, 'hip': 108, 'length': 104}, 'XL': {'waist': 92, 'hip': 114, 'length': 106},
  },
  'falda': {
    'XS': {'waist': 64, 'hip': 92, 'length': 45}, 'S': {'waist': 68, 'hip': 96, 'length': 46},
    'M': {'waist': 72, 'hip': 100, 'length': 47}, 'L': {'waist': 78, 'hip': 106, 'length': 48},
  },
  'short': {
    'S': {'waist': 74, 'hip': 98, 'length': 45}, 'M': {'waist': 80, 'hip': 104, 'length': 46},
    'L': {'waist': 86, 'hip': 110, 'length': 47}, 'XL': {'waist': 92, 'hip': 116, 'length': 48},
  },
};

class ProductForm extends StatefulWidget {
  const ProductForm({super.key, this.product});
  final Product? product;

  @override
  State<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<ProductForm> {
  final _form = GlobalKey<FormState>();
  late final Product? p = widget.product;
  late final _name = TextEditingController(text: p?.name ?? '');
  late final _desc = TextEditingController(text: p?.description ?? '');
  late final _brand = TextEditingController(text: p?.brand ?? '');
  late final _price = TextEditingController(text: p?.price.toStringAsFixed(2) ?? '');
  late final _origin = TextEditingController(text: p?.origin ?? '');
  late final _materials = TextEditingController(text: p?.materials ?? '');
  late final _lensId = TextEditingController(text: p?.tryonLensId ?? '');
  late String _category = p?.category ?? 'polo';
  late String _gender = p?.gender ?? 'unisex';
  late String? _color = p?.color;
  late final Set<String> _styles = {...?p?.styleTags};
  late bool _active = p?.active ?? true;

  // tabla de tallas editable: talla → zona → controlador
  late Map<String, Map<String, TextEditingController>> _chart = _chartControllers();

  Uint8List? _imageBytes;
  bool _removeBg = true;
  bool _processing = false;

  Map<String, Map<String, TextEditingController>> _chartControllers() {
    final source = p != null && p!.category == _category
        ? p!.sizeChart.map((s, m) => MapEntry(s, {...m.toJson().map((k, v) => MapEntry(k, (v as num).toDouble())), 'stock': (p!.stock[s] ?? 0).toDouble()}))
        : _defaultCharts[_category]!.map((s, m) => MapEntry(s, {...m, 'stock': 10.0}));
    return source.map((s, m) => MapEntry(s, m.map((k, v) => MapEntry(k, TextEditingController(text: v.round().toString())))));
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 92);
    if (file == null) return;
    var bytes = await file.readAsBytes();
    if (_removeBg) {
      setState(() => _processing = true);
      try {
        bytes = await removeBackground(bytes);
      } finally {
        if (mounted) setState(() => _processing = false);
      }
    }
    setState(() => _imageBytes = bytes);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (p == null && _imageBytes == null) throw Exception('Agrega una foto de la prenda');
    if (_color == null) throw Exception('Elige el color');
    String? imageUrl = p?.imageUrl;
    if (_imageBytes != null) {
      imageUrl = await Api.uploadImage(_imageBytes!, _removeBg ? 'prenda.png' : 'prenda.jpg', _removeBg ? 'image/png' : 'image/jpeg');
    }
    final sizeChart = <String, dynamic>{};
    final stock = <String, int>{};
    _chart.forEach((size, fields) {
      final m = <String, double>{};
      fields.forEach((k, c) {
        final v = double.tryParse(c.text.replaceAll(',', '.'));
        if (v == null) return;
        k == 'stock' ? stock[size] = v.round() : m[k] = v;
      });
      sizeChart[size] = m;
    });
    final values = {
      'name': _name.text.trim(),
      'description': _desc.text.trim(),
      'brand': _brand.text.trim(),
      'category': _category,
      'gender': _gender,
      'style_tags': _styles.toList(),
      'color': _color,
      'price': double.parse(_price.text.replaceAll(',', '.')),
      'origin': _origin.text.trim(),
      'materials': _materials.text.trim(),
      'size_chart': sizeChart,
      'stock': stock,
      'image_url': imageUrl,
      'tryon_image_url': imageUrl,
      'tryon_type': categoryTryon[_category],
      'tryon_lens_id': _lensId.text.trim().isEmpty ? null : _lensId.text.trim(),
      if (_imageBytes != null) ...{'tryon_anchor': null, 'tryon_rig': null, 'tryon_back_url': null}, // se estiman del contorno
      'active': _active,
    };
    final saved = await Api.saveProduct(values, id: p?.id);
    if (!mounted) return;
    showInfo(context, 'Prenda guardada. Registrando procedencia en Polygon…');
    final res = await Api.registerOnChain(saved.id);
    if (!mounted) return;
    final tx = res['tx_hash'] as String?;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.link, color: AppColors.chain, size: 40),
        title: Text(res['unchanged'] == true ? 'Sin cambios on-chain' : 'Registrada en blockchain'),
        content: Text(res['unchanged'] == true
            ? 'Los datos de procedencia no cambiaron, se mantiene el registro anterior.'
            : 'La huella de la prenda (origen, materiales, proveedor) quedó anclada en Polygon Amoy.'),
        actions: [
          if (tx != null) TextButton(onPressed: () => openExplorerTx(tx), child: const Text('Ver transacción')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Listo')),
        ],
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(p == null ? 'Nueva prenda' : 'Editar prenda')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 40), children: [
          AspectRatio(
            aspectRatio: 1.3,
            child: _processing
                ? const Card(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 10),
                    Text('Quitando el fondo…'),
                  ])))
                : _imageBytes != null
                    ? Container(
                        decoration: BoxDecoration(color: const Color(0xFFEFEBE4), borderRadius: BorderRadius.circular(18)),
                        padding: const EdgeInsets.all(12),
                        child: Image.memory(_imageBytes!, fit: BoxFit.contain),
                      )
                    : p != null
                        ? GarmentImage(p!.imageUrl)
                        : Card(
                            child: Center(
                              child: Column(mainAxisSize: MainAxisSize.min, children: const [
                                Icon(Icons.add_photo_alternate_outlined, size: 44, color: AppColors.muted),
                                SizedBox(height: 6),
                                Text('Foto de la prenda sobre fondo liso', style: TextStyle(color: AppColors.muted)),
                              ]),
                            ),
                          ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Galería'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Cámara'),
              ),
            ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _removeBg,
            onChanged: (v) => setState(() => _removeBg = v),
            title: const Text('Quitar fondo automáticamente'),
            subtitle: const Text('Necesario para que la prenda se vea bien en el probador RA'),
          ),
          const SizedBox(height: 8),
          TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre'), validator: _req),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextFormField(controller: _brand, decoration: const InputDecoration(labelText: 'Marca'), validator: _req)),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Precio', prefixText: 'S/ '),
                validator: (v) => double.tryParse((v ?? '').replaceAll(',', '.')) == null ? 'Precio inválido' : null,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextFormField(controller: _desc, maxLines: 3, decoration: const InputDecoration(labelText: 'Descripción')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Categoría'),
                items: [for (final c in categoryLabels.entries) DropdownMenuItem(value: c.key, child: Text(c.value))],
                onChanged: (v) => setState(() {
                  _category = v!;
                  _chart = _chartControllers();
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _gender,
                decoration: const InputDecoration(labelText: 'Público'),
                items: const [
                  DropdownMenuItem(value: 'unisex', child: Text('Unisex')),
                  DropdownMenuItem(value: 'mujer', child: Text('Mujer')),
                  DropdownMenuItem(value: 'hombre', child: Text('Hombre')),
                ],
                onChanged: (v) => setState(() => _gender = v!),
              ),
            ),
          ]),
          _label('Color'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in colorOptions.entries)
              ChoiceChip(
                avatar: CircleAvatar(backgroundColor: Color(c.value), radius: 8),
                label: Text(c.key),
                selected: _color == c.key,
                onSelected: (_) => setState(() => _color = c.key),
              ),
          ]),
          _label('Estilos (la IA los usa para recomendar)'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in styleOptions)
              FilterChip(
                label: Text(s),
                selected: _styles.contains(s),
                onSelected: (v) => setState(() => v ? _styles.add(s) : _styles.remove(s)),
              ),
          ]),
          _label('Procedencia (se registra en blockchain)'),
          TextFormField(
            controller: _origin,
            decoration: const InputDecoration(labelText: 'Lugar de fabricación', hintText: 'Ej. Gamarra, Lima - Perú'),
            validator: _req,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _materials,
            decoration: const InputDecoration(labelText: 'Materiales', hintText: 'Ej. 100% algodón pima'),
            validator: _req,
          ),
          _label('Probador 3D (opcional)'),
          TextFormField(
            controller: _lensId,
            decoration: const InputDecoration(
              labelText: 'ID del lente de Snap (Lens Studio)',
              helperText: 'Si lo completas, los compradores verán "Probar en 3D"',
            ),
          ),
          _label('Tabla de tallas (cm) y stock'),
          _chartEditor(),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _active,
            onChanged: (v) => setState(() => _active = v),
            title: const Text('Visible en el catálogo'),
          ),
          const SizedBox(height: 16),
          BusyButton(label: 'Guardar y registrar en blockchain', icon: Icons.link, onPressed: _processing ? null : _save),
        ]),
      ),
    );
  }

  String? _req(String? v) => v == null || v.trim().isEmpty ? 'Requerido' : null;

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 10),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
      );

  Widget _chartEditor() {
    const names = {'chest': 'Pecho', 'waist': 'Cintura', 'hip': 'Cadera', 'length': 'Largo', 'stock': 'Stock'};
    final cols = _chart.values.isEmpty ? <String>[] : _chart.values.first.keys.toList();
    cols.sort((a, b) => names.keys.toList().indexOf(a).compareTo(names.keys.toList().indexOf(b)));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          Row(children: [
            const SizedBox(width: 44, child: Text('Talla', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
            for (final c in cols)
              Expanded(child: Text(names[c]!, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
          ]),
          for (final s in sortSizes(_chart.keys))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                SizedBox(width: 44, child: Text(s, style: const TextStyle(fontWeight: FontWeight.w700))),
                for (final c in cols)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: TextField(
                        controller: _chart[s]![c],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 10)),
                      ),
                    ),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }
}
