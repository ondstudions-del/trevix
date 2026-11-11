import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trevix/widgets/media.dart';

const _screen = Size(393, 852);

Future<File> _landscapePng() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 1890, 1000), Paint()..color = const Color(0xFF7C3AED));
  final image = await recorder.endRecording().toImage(1890, 1000);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${Directory.systemTemp.createTempSync('trevix').path}/foto.png');
  await file.writeAsBytes(data!.buffer.asUint8List());
  return file;
}

/// Rectángulo de la pantalla donde queda pintada la foto.
Rect _painted(WidgetTester tester) {
  final box = tester.renderObject<RenderImage>(find.byType(RawImage));
  final img = box.image!;
  final fitted = applyBoxFit(BoxFit.contain, Size(img.width.toDouble(), img.height.toDouble()), box.size).destination;
  final local = Alignment.center.inscribe(fitted, Offset.zero & box.size);
  return Rect.fromPoints(box.localToGlobal(local.topLeft), box.localToGlobal(local.bottomRight));
}

void main() {
  late File photo;

  setUpAll(() async => photo = await _landscapePng());

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = _screen * 3;
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
    tester.view.viewPadding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(PageRouteBuilder<void>(
                opaque: false,
                barrierColor: Colors.black,
                pageBuilder: (_, __, ___) => MediaViewer.file(photo),
              )),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.runAsync(() async {
      await tester.pump();
      bool ready() => find.byType(RawImage).evaluate().isNotEmpty && tester.renderObject<RenderImage>(find.byType(RawImage)).image != null;
      for (var i = 0; i < 40 && !ready(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
  }

  void expectCentered(WidgetTester tester, String when) {
    final r = _painted(tester);
    expect(r.width, moreOrLessEquals(_screen.width, epsilon: .5), reason: '$when: ancho $r');
    expect(r.center.dx, moreOrLessEquals(_screen.width / 2, epsilon: .5), reason: '$when: $r');
    expect(r.center.dy, moreOrLessEquals(_screen.height / 2, epsilon: .5), reason: '$when: $r');
  }

  testWidgets('la foto abre centrada y ajustada a la pantalla', (tester) async {
    await open(tester);
    expectCentered(tester, 'al abrir');
  });

  testWidgets('arrastrar un poco y soltar la deja en su sitio', (tester) async {
    await open(tester);
    await tester.dragFrom(const Offset(200, 430), const Offset(0, -80));
    await tester.pumpAndSettle();
    expectCentered(tester, 'tras arrastrar hacia arriba');
    await tester.dragFrom(const Offset(200, 430), const Offset(30, 60));
    await tester.pumpAndSettle();
    expectCentered(tester, 'tras arrastrar en diagonal');
  });

  testWidgets('pellizcar para alejar no la achica ni la mueve', (tester) async {
    await open(tester);
    final a = await tester.startGesture(const Offset(120, 300));
    final b = await tester.startGesture(const Offset(270, 560), pointer: 2);
    for (var i = 0; i < 10; i++) {
      await a.moveBy(const Offset(6, 4));
      await b.moveBy(const Offset(-6, -14));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expectCentered(tester, 'tras pellizcar para alejar');
  });

  testWidgets('doble toque amplía y otro doble toque la devuelve', (tester) async {
    await open(tester);
    Future<void> doubleTap() async {
      await tester.tapAt(const Offset(150, 300));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(const Offset(150, 300));
      await tester.pumpAndSettle();
    }

    await doubleTap();
    expect(_painted(tester).width, greaterThan(_screen.width * 2));
    await doubleTap();
    expectCentered(tester, 'tras el segundo doble toque');
  });
}
