import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import 'scan_flow.dart';

/// Where a receipt comes from: the camera opens straight away, with the
/// gallery one tap away in the corner, so taking a photo and picking one
/// already on the phone are the same screen rather than a menu first.
///
/// Pops with the snapshots taken or picked, or with nothing when closed.
class CameraCaptureScreen extends StatefulWidget {
  /// Finds the cameras. Injectable so a test can run without one.
  final Future<List<CameraDescription>> Function() loadCameras;

  /// Picks pictures already on the phone.
  final Future<List<Uint8List>> Function() pickFromGallery;

  const CameraCaptureScreen({
    super.key,
    this.loadCameras = availableCameras,
    this.pickFromGallery = _pickFromGallery,
  });

  static Future<List<Uint8List>> _pickFromGallery() =>
      pickScanImages(ScanSource.gallery);

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  CameraController? _controller;
  bool _failed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final cameras = await widget.loadCameras();
      if (cameras.isEmpty) throw StateError('no camera');
      // The back camera, when there is one: receipts are shot away from you.
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      // No camera, no permission, or a browser that will not give one:
      // the gallery still works, so the screen stays and says so.
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _shoot() async {
    final controller = _controller;
    if (controller == null || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      if (mounted) Navigator.of(context).pop(<Uint8List>[bytes]);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сделать снимок')),
        );
      }
    }
  }

  Future<void> _gallery() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await widget.pickFromGallery();
      if (!mounted) return;
      if (picked.isEmpty) {
        setState(() => _busy = false);
        return;
      }
      Navigator.of(context).pop(picked);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: controller != null
                  ? Center(child: CameraPreview(controller))
                  : Center(
                      child: _failed
                          ? const Padding(
                              padding: EdgeInsets.all(32),
                              child: Text(
                                'Камера недоступна.\n'
                                'Выберите фото чека из галереи.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 15,
                                ),
                              ),
                            )
                          : const CircularProgressIndicator(
                              color: Colors.white70,
                            ),
                    ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(<Uint8List>[]),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                tooltip: 'Закрыть',
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    onPressed: _gallery,
                    iconSize: 30,
                    icon: const Icon(
                      Icons.photo_library_outlined,
                      color: Colors.white,
                    ),
                    tooltip: 'Выбрать из галереи',
                  ),
                  _Shutter(
                    enabled: controller != null && !_busy,
                    onPressed: _shoot,
                  ),
                  // Balances the gallery button so the shutter is centred.
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Shutter extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPressed;

  const _Shutter({required this.enabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Снять чек',
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
            ),
            padding: const EdgeInsets.all(5),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kChampagne,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
