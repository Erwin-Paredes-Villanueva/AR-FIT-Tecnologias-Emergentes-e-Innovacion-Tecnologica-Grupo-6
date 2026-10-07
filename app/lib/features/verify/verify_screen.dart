import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/api.dart';
import '../../core/chain_reader.dart';
import '../../core/labels.dart';
import '../../core/models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../product/product_detail.dart';
import 'authenticity_card.dart';

/// Verificación phygital: escanea la etiqueta QR de la prenda física y
/// comprueba su registro en Polygon Amoy.
class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key});

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  Product? _product;
  bool _loading = false;
  String? _error;
  int? _block;

  @override
  void initState() {
    super.initState();
    ChainReader().latestBlock().then((b) => mounted ? setState(() => _block = b) : null).catchError((_) => null);
  }

  Future<void> _lookup(String code) async {
    final id = code.replaceFirst('arfit://product/', '').trim();
    if (!RegExp(r'^[0-9a-f-]{36}$').hasMatch(id)) {
      setState(() => _error = 'El código no es una etiqueta AR-FIT');
      return;
    }
    setState(() => (_loading = true, _error = null));
    try {
      final p = await Api.product(id);
      setState(() {
        _product = p;
        _error = p == null ? 'La prenda no existe en el catálogo' : null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const _ScannerPage()));
    if (code != null) await _lookup(code);
  }

  @override
  Widget build(BuildContext context) {
    final p = _product;
    return Scaffold(
      appBar: AppBar(title: const Text('Verificar autenticidad')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.chain.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.qr_code_scanner, size: 40, color: AppColors.chain),
              ),
              const SizedBox(height: 12),
              const Text('Escanea la etiqueta de la prenda', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text(
                'Cada prenda física lleva un QR que apunta a su registro inmutable en blockchain: origen, materiales, proveedor y verificación.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.chain),
                  onPressed: _loading ? null : _scan,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Escanear QR'),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.circle, size: 10, color: AppColors.chain),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _block == null ? 'Conectando con Polygon Amoy…' : 'Conectado a Polygon Amoy · bloque #$_block',
              style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
            ),
          ),
          TextButton(onPressed: openExplorerContract, child: const Text('Ver contrato')),
        ]),
        if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
          ),
        if (p != null && !_loading) ...[
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: SizedBox(width: 56, height: 56, child: GarmentImage(p.imageUrl, padding: 4, radius: 10)),
            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${p.brand} · ${money.format(p.price)}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetail(product: p))),
          ),
          AuthenticityCard(key: ValueKey(p.id), product: p),
        ],
      ]),
    );
  }
}

class _ScannerPage extends StatefulWidget {
  const _ScannerPage();

  @override
  State<_ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<_ScannerPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear etiqueta')),
      body: Stack(children: [
        MobileScanner(
          onDetect: (capture) {
            final code = capture.barcodes.firstOrNull?.rawValue;
            if (code == null || _done) return;
            _done = true;
            Navigator.pop(context, code);
          },
        ),
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(24)),
          ),
        ),
      ]),
    );
  }
}
