import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'common.dart';

/// Escáner de cámara con alternativas: leer el código desde una foto de la
/// galería o escribirlo a mano (útil si la etiqueta está dañada).
class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key, required this.title, required this.hint, required this.formats, this.allowTyping = false});
  final String title, hint;
  final List<BarcodeFormat> formats;
  final bool allowTyping;

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  late final _controller = MobileScannerController(formats: widget.formats);
  bool _done = false;

  void _finish(String? code) {
    if (code == null || code.isEmpty || _done) return;
    _done = true;
    Navigator.pop(context, code);
  }

  Future<void> _fromPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final capture = await _controller.analyzeImage(file.path, formats: widget.formats);
    final code = capture?.barcodes.firstOrNull?.rawValue;
    if (!mounted) return;
    if (code == null) {
      showError(context, 'No se encontró un código en la foto');
    } else {
      _finish(code);
    }
  }

  Future<void> _type() async {
    final ctl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Escribe los 13 dígitos'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 13,
          decoration: const InputDecoration(hintText: '7750…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Listo')),
        ],
      ),
    );
    _finish(code);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barcode = !widget.formats.contains(BarcodeFormat.qrCode);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(children: [
        MobileScanner(controller: _controller, onDetect: (capture) => _finish(capture.barcodes.firstOrNull?.rawValue)),
        Center(
          child: Container(
            width: barcode ? 300 : 240,
            height: barcode ? 150 : 240,
            decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(20)),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: SafeArea(
            child: Column(children: [
              Text(widget.hint, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: FilledButton.tonalIcon(onPressed: _fromPhoto, icon: const Icon(Icons.photo_library_outlined), label: const Text('Desde una foto')),
                ),
                if (widget.allowTyping) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonalIcon(onPressed: _type, icon: const Icon(Icons.keyboard_outlined), label: const Text('Escribirlo')),
                  ),
                ],
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}
