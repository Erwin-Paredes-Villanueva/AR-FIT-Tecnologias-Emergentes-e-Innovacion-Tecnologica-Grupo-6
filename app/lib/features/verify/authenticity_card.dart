import 'package:flutter/material.dart';

import '../../core/chain_reader.dart';
import '../../core/labels.dart';
import '../../core/models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Certificado de autenticidad: lee el contrato en Polygon Amoy y compara la
/// huella de la ficha mostrada con la registrada on-chain.
class AuthenticityCard extends StatefulWidget {
  const AuthenticityCard({super.key, required this.product});
  final Product product;

  @override
  State<AuthenticityCard> createState() => _AuthenticityCardState();
}

class _AuthenticityCardState extends State<AuthenticityCard> {
  late Future<ChainProduct> _future = ChainReader().getProduct(widget.product.id);

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<ChainProduct>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Row(children: [
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 12),
                Text('Consultando Polygon Amoy…'),
              ]);
            }
            if (snap.hasError) {
              return Row(children: [
                const Icon(Icons.cloud_off, color: AppColors.muted),
                const SizedBox(width: 12),
                const Expanded(child: Text('No se pudo consultar la blockchain')),
                TextButton(
                  onPressed: () => setState(() => _future = ChainReader().getProduct(p.id)),
                  child: const Text('Reintentar'),
                ),
              ]);
            }
            final c = snap.data!;
            if (!c.exists) {
              return const Row(children: [
                Icon(Icons.hourglass_top, color: Colors.orange),
                SizedBox(width: 12),
                Expanded(child: Text('Esta prenda aún no ha sido registrada en blockchain.')),
              ]);
            }
            final intact = c.dataHash.toLowerCase() == productDataHash(p).toLowerCase();
            final ok = intact && c.verified;
            final color = ok ? AppColors.chain : (intact ? Colors.orange.shade700 : Colors.red.shade700);
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(ok ? Icons.verified : (intact ? Icons.pending : Icons.gpp_bad), color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      ok
                          ? 'Prenda auténtica verificada'
                          : intact
                              ? 'Registrada, pendiente de verificación'
                              : '¡La ficha no coincide con el registro!',
                      style: TextStyle(fontWeight: FontWeight.w700, color: color),
                    ),
                    const Text('Datos leídos directamente de Polygon Amoy', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  ]),
                ),
              ]),
              const Divider(height: 24),
              _row(Icons.place_outlined, 'Origen', c.origin),
              _row(Icons.texture, 'Materiales', c.materials),
              _row(Icons.event_outlined, 'Registrada', dateTimeFmt.format(c.registeredAt)),
              _row(Icons.fingerprint, 'Huella', shortHash(c.dataHash, 8), mono: true),
              _row(intact ? Icons.check_circle_outline : Icons.error_outline, 'Integridad',
                  intact ? 'La ficha coincide con la huella on-chain' : 'Los datos fueron modificados'),
              if (p.chainTx != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => openExplorerTx(p.chainTx!),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Ver en PolygonScan'),
                  ),
                ),
            ]);
          },
        ),
      ),
    );
  }

  Widget _row(IconData icon, String k, String v, {bool mono = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: AppColors.muted),
          const SizedBox(width: 10),
          SizedBox(width: 86, child: Text(k, style: const TextStyle(color: AppColors.muted))),
          Expanded(
            child: Text(v,
                style: TextStyle(fontWeight: FontWeight.w500, fontFamily: mono ? 'monospace' : null, fontSize: mono ? 12.5 : null)),
          ),
        ]),
      );
}
