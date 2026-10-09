import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/screens/camera_capture_screen.dart';

void main() {
  Future<List<Uint8List>?> open(
    WidgetTester tester, {
    required Future<List<Uint8List>> Function() gallery,
  }) async {
    List<Uint8List>? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await Navigator.of(context).push<List<Uint8List>>(
              MaterialPageRoute(
                builder: (_) => CameraCaptureScreen(
                  // No camera in a test: the screen must still offer the
                  // gallery.
                  loadCameras: () async => <CameraDescription>[],
                  pickFromGallery: gallery,
                ),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('without a camera it says so and still offers the gallery',
      (tester) async {
    await open(tester, gallery: () async => const []);
    expect(find.textContaining('Камера недоступна'), findsOneWidget);
    expect(find.byTooltip('Выбрать из галереи'), findsOneWidget);
    expect(find.bySemanticsLabel('Снять чек'), findsOneWidget);
  });

  testWidgets('a picture picked from the gallery comes back from the screen',
      (tester) async {
    final picture = Uint8List.fromList([1, 2, 3]);
    List<Uint8List>? got;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            got = await Navigator.of(context).push<List<Uint8List>>(
              MaterialPageRoute(
                builder: (_) => CameraCaptureScreen(
                  loadCameras: () async => <CameraDescription>[],
                  pickFromGallery: () async => [picture],
                ),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Выбрать из галереи'));
    await tester.pumpAndSettle();
    expect(got, [picture]);
  });

  testWidgets('closing hands back nothing', (tester) async {
    List<Uint8List>? got;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            got = await Navigator.of(context).push<List<Uint8List>>(
              MaterialPageRoute(
                builder: (_) => CameraCaptureScreen(
                  loadCameras: () async => <CameraDescription>[],
                  pickFromGallery: () async => const [],
                ),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();
    expect(got, isEmpty);
  });
}
