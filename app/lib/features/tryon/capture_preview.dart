// Vista previa de una captura del probador (2D o 3D): guardar en galería o compartir.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../theme.dart';
import '../../widgets/common.dart';

class CapturePreview extends StatefulWidget {
  /// Foto compuesta en la app (probador 2D).
  const CapturePreview.bytes(Uint8List this.bytes, {super.key, required this.title})
      : file = null,
        isVideo = false;

  /// Foto o video devuelto por la cámara de Snap (probador 3D).
  const CapturePreview.file(File this.file, {super.key, required this.title, this.isVideo = false}) : bytes = null;

  final Uint8List? bytes;
  final File? file;
  final bool isVideo;
  final String title;

  @override
  State<CapturePreview> createState() => _CapturePreviewState();
}

class _CapturePreviewState extends State<CapturePreview> {
  bool _saved = false;
  File? _file;

  /// Archivo en disco (lo necesitan la galería y el menú de compartir).
  Future<File> _ensureFile() async {
    if (_file != null) return _file!;
    if (widget.file != null) return _file = widget.file!;
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/arfit_${DateTime.now().millisecondsSinceEpoch}.png');
    await f.writeAsBytes(widget.bytes!);
    return _file = f;
  }

  Future<void> _save() async {
    try {
      if (!await Gal.hasPermission(toAlbum: true) && !await Gal.requestPermission(toAlbum: true)) {
        if (mounted) showError(context, 'Necesitamos permiso para guardar en tu galería');
        return;
      }
      final f = await _ensureFile();
      widget.isVideo ? await Gal.putVideo(f.path, album: 'AR-FIT') : await Gal.putImage(f.path, album: 'AR-FIT');
      if (!mounted) return;
      setState(() => _saved = true);
      showInfo(context, widget.isVideo ? 'Video guardado en tu galería (álbum AR-FIT)' : 'Foto guardada en tu galería (álbum AR-FIT)');
    } on GalException catch (e) {
      if (mounted) showError(context, 'No se pudo guardar: ${e.type.message}');
    }
  }

  Future<void> _share() async {
    final f = await _ensureFile();
    await SharePlus.instance.share(ShareParams(
      files: [XFile(f.path)],
      text: 'Así me queda "${widget.title}" en el probador virtual de AR-FIT',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.isVideo ? 'Tu video' : 'Tu foto', style: const TextStyle(color: Colors.white)),
      ),
      body: Column(children: [
        Expanded(
          child: Center(
            child: widget.isVideo
                ? const Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.videocam, color: Colors.white54, size: 72),
                    SizedBox(height: 12),
                    Text('Video grabado con el probador 3D', style: TextStyle(color: Colors.white70)),
                  ])
                : InteractiveViewer(
                    child: widget.bytes != null ? Image.memory(widget.bytes!) : Image.file(widget.file!),
                  ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                  onPressed: _share,
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Compartir'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: BusyButton(
                  label: _saved ? 'Guardada' : 'Guardar',
                  icon: _saved ? Icons.check : Icons.download,
                  color: AppColors.accent,
                  onPressed: _saved ? null : _save,
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
