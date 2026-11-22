import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/chain_reader.dart';
import '../../core/labels.dart';
import '../../core/models.dart';
import '../../core/unit_label.dart';
import '../../theme.dart';
import '../../widgets/barcode_scanner_page.dart';
import '../../widgets/common.dart';
import '../product/product_detail.dart';
import 'authenticity_card.dart';

/// Verificación anti-fraude de una prenda física, en 3 capas:
///   1) QR único de la unidad, firmado por AR-FIT (la firma se comprueba en el
///      teléfono) y registrado en Polygon Amoy (contrato ARFitUnits)
///   2) código de barras EAN-13 de la etiqueta: debe ser el de esa prenda y talla
///   3) activación: si la unidad ya tiene dueño, una "nueva" sería una copia
class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key});

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  bool _loading = false;
  String? _error;
  int? _block;

  // etiqueta antigua (solo identifica el modelo)
  Product? _legacyProduct;
  // etiqueta de unidad (verificación completa)
  _UnitCheck? _check;

  @override
  void initState() {
    super.initState();
    ChainReader().latestBlock().then((b) => mounted ? setState(() => _block = b) : null).catchError((_) => null);
  }

  Future<void> _scanQr() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerPage(
          title: 'Escanear QR de la etiqueta',
          hint: 'Apunta al código QR de la etiqueta AR-FIT',
          formats: [BarcodeFormat.qrCode],
        ),
      ),
    );
    if (code != null) await _lookup(code);
  }

  Future<void> _lookup(String code) async {
    setState(() {
      _loading = true;
      _error = null;
      _legacyProduct = null;
      _check = null;
    });
    try {
      final label = UnitLabel.tryParse(code);
      if (label != null) {
        final check = _UnitCheck(label, myId: context.read<AppState>().profile?.id);
        await check.load();
        setState(() => _check = check);
        return;
      }
      final id = code.replaceFirst('arfit://product/', '').trim();
      if (!RegExp(r'^[0-9a-f-]{36}$').hasMatch(id)) {
        setState(() => _error = 'El código no es una etiqueta AR-FIT');
        return;
      }
      final p = await Api.product(id);
      setState(() {
        _legacyProduct = p;
        _error = p == null ? 'La prenda no existe en el catálogo' : null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scanBarcode() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerPage(
          title: 'Escanear código de barras',
          hint: 'Apunta al código de barras de la etiqueta de la prenda',
          formats: [BarcodeFormat.ean13, BarcodeFormat.upcA],
          allowTyping: true,
        ),
      ),
    );
    if (code == null || _check == null) return;
    // UPC-A (12 dígitos) es un EAN-13 con un 0 delante
    final digits = code.replaceAll(RegExp(r'\D'), '');
    setState(() => _check!.barcode = digits.length == 12 ? '0$digits' : digits);
  }

  Future<void> _claim() async {
    final c = _check!;
    await Api.claimUnit(c.label.serial);
    await c.load();
    if (!mounted) return;
    setState(() {});
    showInfo(context, 'Prenda activada a tu nombre en Polygon Amoy');
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AppState>().profile;
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
              const Text('¿Tu prenda es original?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text(
                'Escanea el QR de su etiqueta y luego el código de barras. Comprobamos la firma de AR-FIT, '
                'el registro en blockchain y que nadie más la haya activado.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.chain),
                  onPressed: _loading ? null : _scanQr,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: Text(_check == null ? 'Escanear QR de la etiqueta' : 'Escanear otra prenda'),
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
        if (_check != null && !_loading) ..._unitResult(_check!, profile),
        if (_legacyProduct != null && !_loading) ..._legacyResult(_legacyProduct!),
      ]),
    );
  }

  List<Widget> _unitResult(_UnitCheck c, Profile? profile) {
    final v = c.verdict;
    final p = c.product;
    return [
      const SizedBox(height: 12),
      _VerdictBanner(verdict: v),
      const SizedBox(height: 12),
      if (p != null)
        Card(
          child: ListTile(
            leading: SizedBox(width: 52, height: 52, child: GarmentImage(p.imageUrl, padding: 4, radius: 10)),
            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${p.brand} · talla ${c.label.size}\nSerie ${c.label.serial}'),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetail(product: p))),
          ),
        ),
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Comprobaciones', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            for (final s in c.steps) _StepRow(step: s),
          ]),
        ),
      ),
      if (c.signatureOk && c.chainMatches) ...[
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: _scanBarcode,
          icon: const Icon(Icons.barcode_reader),
          label: Text(c.barcode == null ? 'Escanear código de barras de la etiqueta' : 'Volver a escanear el código de barras'),
        ),
      ],
      if (c.canClaim && profile != null && profile.isBuyer && v.level != _Level.fail) ...[
        const SizedBox(height: 8),
        BusyButton(label: 'Es mía: activar a mi nombre', icon: Icons.verified_user_outlined, color: AppColors.chain, onPressed: _claim),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'Solo puedes activarla si la compraste en AR-FIT y ya te la entregaron. '
            'Una vez activada, cualquier copia de esta etiqueta quedará en evidencia.',
            style: TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
        ),
      ],
      if (p != null) ...[
        const SizedBox(height: 12),
        AuthenticityCard(key: ValueKey(p.id), product: p),
      ],
    ];
  }

  List<Widget> _legacyResult(Product p) => [
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
          child: const Row(children: [
            Icon(Icons.info_outline, color: Colors.orange),
            SizedBox(width: 10),
            Expanded(
              child: Text('Este QR solo identifica el modelo de la prenda, no la unidad. '
                  'Para comprobar que tu prenda es original, escanea la etiqueta con número de serie.'),
            ),
          ]),
        ),
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
      ];
}

// ---------------------------------------------------------------- lógica

enum _Level { ok, warn, pending, fail }

class _Step {
  final String title, detail;
  final _Level level;
  const _Step(this.title, this.detail, this.level);
}

class _Verdict {
  final _Level level;
  final String title, message;
  const _Verdict(this.level, this.title, this.message);
}

class _UnitCheck {
  _UnitCheck(this.label, {this.myId});
  final UnitLabel label;
  final String? myId;

  String? signer;
  ChainUnit? unit;
  Object? chainError;
  Product? product;
  String? barcode;

  Future<void> load() async {
    signer = label.signer;
    try {
      unit = await ChainReader().getUnit(label.unitId);
      chainError = null;
    } catch (e) {
      chainError = e;
    }
    product ??= await Api.product(label.productId).catchError((_) => null);
  }

  bool get signatureOk => signer != null && signer!.toLowerCase() == AppConfig.labelIssuer.toLowerCase();

  bool get chainMatches {
    final u = unit;
    return u != null &&
        u.exists &&
        u.productRef.toLowerCase() == chainRef(label.productId).toLowerCase() &&
        u.size == label.size &&
        u.gtin == label.gtin;
  }

  bool get mine => myId != null && unit != null && unit!.claimed && unit!.ownerRef.toLowerCase() == chainRef(myId!).toLowerCase();
  bool get canClaim => signatureOk && chainMatches && !(unit?.claimed ?? true);

  List<_Step> get steps {
    final u = unit;
    return [
      signatureOk
          ? const _Step('Firma de AR-FIT', 'La etiqueta fue emitida por AR-FIT y no fue alterada', _Level.ok)
          : const _Step('Firma de AR-FIT', 'La firma no es de AR-FIT: etiqueta falsificada o modificada', _Level.fail),
      if (chainError != null)
        const _Step('Registro en blockchain', 'No se pudo consultar Polygon Amoy. Revisa tu conexión', _Level.pending)
      else if (u == null || !u.exists)
        const _Step('Registro en blockchain', 'Esta serie no existe en el contrato ARFitUnits', _Level.fail)
      else if (!chainMatches)
        const _Step('Registro en blockchain', 'Los datos del QR no coinciden con el registro on-chain', _Level.fail)
      else
        _Step('Registro en blockchain', 'Unidad registrada el ${dateTimeFmt.format(u.issuedAt)} (talla ${u.size})', _Level.ok),
      if (barcode == null)
        _Step('Código de barras', 'Escanéalo para comparar con el esperado: ${label.gtin}', _Level.pending)
      else if (!isValidEan13(barcode!))
        _Step('Código de barras', '$barcode no es un EAN-13 válido', _Level.fail)
      else if (barcode != label.gtin)
        _Step('Código de barras', 'La etiqueta dice $barcode, pero esta prenda y talla usan ${label.gtin}', _Level.fail)
      else
        _Step('Código de barras', '$barcode coincide con la prenda y la talla', _Level.ok),
      if (u != null && u.exists)
        if (!u.claimed)
          const _Step('Activación', 'Nueva: todavía nadie la ha activado como suya', _Level.ok)
        else if (mine)
          _Step('Activación', 'Activada a tu nombre el ${dateTimeFmt.format(u.claimedAt!)}', _Level.ok)
        else
          _Step('Activación', 'Ya fue activada por otro comprador el ${dateTimeFmt.format(u.claimedAt!)}', _Level.warn),
    ];
  }

  _Verdict get verdict {
    final levels = steps.map((s) => s.level).toSet();
    if (levels.contains(_Level.fail)) {
      return const _Verdict(_Level.fail, 'No verificada: posible falsificación',
          'Al menos una comprobación falló. No la compres como original y repórtala a la tienda.');
    }
    if (levels.contains(_Level.warn)) {
      return const _Verdict(_Level.warn, 'Atención: esta prenda ya tiene dueño',
          'La etiqueta es real, pero ya fue activada. Si te la venden como nueva, podría ser una copia de la etiqueta.');
    }
    if (levels.contains(_Level.pending)) {
      return const _Verdict(_Level.pending, 'Falta una comprobación',
          'La firma y el registro son correctos. Escanea el código de barras para completar la verificación.');
    }
    return const _Verdict(_Level.ok, 'Prenda auténtica',
        'Firma de AR-FIT válida, registrada en blockchain y código de barras correcto.');
  }
}

// ---------------------------------------------------------------- widgets

Color _color(_Level l) => switch (l) {
      _Level.ok => AppColors.chain,
      _Level.warn => Colors.orange.shade700,
      _Level.pending => AppColors.muted,
      _Level.fail => Colors.red.shade700,
    };

IconData _icon(_Level l) => switch (l) {
      _Level.ok => Icons.check_circle,
      _Level.warn => Icons.warning_amber_rounded,
      _Level.pending => Icons.radio_button_unchecked,
      _Level.fail => Icons.cancel,
    };

class _VerdictBanner extends StatelessWidget {
  const _VerdictBanner({required this.verdict});
  final _Verdict verdict;

  @override
  Widget build(BuildContext context) {
    final color = _color(verdict.level);
    final icon = switch (verdict.level) {
      _Level.ok => Icons.verified,
      _Level.warn => Icons.gpp_maybe,
      _Level.pending => Icons.pending,
      _Level.fail => Icons.gpp_bad,
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 44),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(verdict.title, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 4),
            Text(verdict.message, style: const TextStyle(height: 1.35)),
          ]),
        ),
      ]),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});
  final _Step step;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(_icon(step.level), color: _color(step.level), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(step.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(step.detail, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            ]),
          ),
        ]),
      );
}
