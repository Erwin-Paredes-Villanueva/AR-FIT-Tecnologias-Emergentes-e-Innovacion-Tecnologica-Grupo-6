import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api.dart';
import '../../core/labels.dart';
import '../../core/models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/ean13_barcode.dart';

/// Etiquetas anti-fraude de una prenda (proveedor): cada unidad física recibe
/// un QR único firmado por AR-FIT y registrado en Polygon Amoy, junto con el
/// código de barras de su talla.
class LabelsScreen extends StatefulWidget {
  const LabelsScreen({super.key, required this.product});
  final Product product;

  @override
  State<LabelsScreen> createState() => _LabelsScreenState();
}

class _LabelsScreenState extends State<LabelsScreen> {
  List<ProductUnit>? _units;
  late String _size = widget.product.sizes.isNotEmpty ? widget.product.sizes.first : 'M';
  int _count = 2;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await Api.productUnits(widget.product.id);
    if (mounted) setState(() => _units = list);
  }

  Future<void> _issue() async {
    final res = await Api.issueUnits(widget.product.id, _size, _count);
    if (!mounted) return;
    showInfo(context, '${(res['units'] as List).length} etiquetas registradas en Polygon Amoy');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final units = _units;
    return Scaffold(
      appBar: AppBar(title: const Text('Etiquetas anti-fraude')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
          Text(p.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'Cada prenda física lleva su propia etiqueta: un QR con número de serie único firmado por AR-FIT '
            'y el código de barras de su talla. El comprador la escanea para comprobar que es original.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Emitir etiquetas', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _size,
                      decoration: const InputDecoration(labelText: 'Talla'),
                      items: [for (final s in p.sizes) DropdownMenuItem(value: s, child: Text(s))],
                      onChanged: (v) => setState(() => _size = v!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _count,
                      decoration: const InputDecoration(labelText: 'Cantidad'),
                      items: [for (final n in [1, 2, 3, 5, 10]) DropdownMenuItem(value: n, child: Text('$n'))],
                      onChanged: (v) => setState(() => _count = v!),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(
                  p.gtins[_size] != null
                      ? 'Código de barras de la talla $_size: ${p.gtins[_size]}'
                      : 'Si la talla no tiene código de barras, AR-FIT le asigna uno EAN-13.',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: BusyButton(label: 'Emitir y registrar en blockchain', icon: Icons.link, color: AppColors.chain, onPressed: _issue),
                ),
              ]),
            ),
          ),
          const SectionTitle('Etiquetas emitidas'),
          if (units == null)
            const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
          else if (units.isEmpty)
            const EmptyState(icon: Icons.qr_code_2, title: 'Aún no hay etiquetas', message: 'Emite etiquetas para las prendas que vas a vender')
          else
            for (final u in units) _UnitTile(product: p, unit: u),
        ]),
      ),
    );
  }
}

class _UnitTile extends StatelessWidget {
  const _UnitTile({required this.product, required this.unit});
  final Product product;
  final ProductUnit unit;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const Icon(Icons.qr_code_2, size: 34),
        title: Text(unit.serial, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700)),
        subtitle: Text('Talla ${unit.size} · ${unit.gtin}'),
        trailing: unit.claimedAt != null
            ? const Pill('Activada', icon: Icons.person, color: AppColors.chain)
            : const Pill('Disponible', color: AppColors.muted),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LabelPreview(product: product, unit: unit))),
      ),
    );
  }
}

/// Etiqueta lista para imprimir o compartir (PNG).
class LabelPreview extends StatefulWidget {
  const LabelPreview({super.key, required this.product, required this.unit});
  final Product product;
  final ProductUnit unit;

  @override
  State<LabelPreview> createState() => _LabelPreviewState();
}

class _LabelPreviewState extends State<LabelPreview> {
  final _key = GlobalKey();

  Future<void> _share() async {
    final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 4);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/etiqueta_${widget.unit.serial}.png');
    await f.writeAsBytes(png!.buffer.asUint8List());
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: 'Etiqueta AR-FIT ${widget.unit.serial}'));
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.unit;
    return Scaffold(
      appBar: AppBar(title: Text(u.serial)),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Center(child: RepaintBoundary(key: _key, child: GarmentLabel(product: widget.product, unit: u))),
        const SizedBox(height: 18),
        if (u.issueTx != null)
          ListTile(
            leading: const Icon(Icons.link, color: AppColors.chain),
            title: const Text('Registrada en Polygon Amoy'),
            subtitle: Text(shortHash(u.issueTx!, 10), style: const TextStyle(fontFamily: 'monospace')),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => openExplorerTx(u.issueTx!),
          ),
        if (u.claimedAt != null)
          ListTile(
            leading: const Icon(Icons.person_pin_circle_outlined, color: AppColors.chain),
            title: const Text('Activada por su comprador'),
            subtitle: Text(dateTimeFmt.format(u.claimedAt!.toLocal())),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: _share, icon: const Icon(Icons.ios_share), label: const Text('Compartir / imprimir etiqueta')),
      ]),
    );
  }
}

/// Diseño de la etiqueta física: marca, prenda, QR firmado, serie y código de barras.
class GarmentLabel extends StatelessWidget {
  const GarmentLabel({super.key, required this.product, required this.unit});
  final Product product;
  final ProductUnit unit;

  @override
  Widget build(BuildContext context) {
    const ink = TextStyle(color: Colors.black);
    return Container(
      width: 300,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(8)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Text('AR-FIT', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1)),
          const Spacer(),
          Text('TALLA ${unit.size}', style: ink.copyWith(fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 2),
        Align(alignment: Alignment.centerLeft, child: Text('${product.name} · ${product.brand}', style: ink.copyWith(fontSize: 12))),
        const SizedBox(height: 10),
        QrImageView(data: unit.qrPayload, size: 190, backgroundColor: Colors.white, errorCorrectionLevel: QrErrorCorrectLevel.M),
        Text(unit.serial, style: ink.copyWith(fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 1.5)),
        const SizedBox(height: 2),
        Text('Escanea con la app AR-FIT para verificar', style: ink.copyWith(fontSize: 10.5)),
        const SizedBox(height: 10),
        Ean13Barcode(unit.gtin, height: 56, moduleWidth: 2.2),
      ]),
    );
  }
}
