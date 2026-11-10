// Pruebas en el simulador de iPhone y el emulador de Android (CI): abrir y cerrar el visor de historias no debe
// cerrar la app. El emulador corre sin animaciones del sistema, así que también cubren «Quitar animaciones».
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:trevix/core/nav.dart';
import 'package:trevix/models/models.dart';
import 'package:trevix/screens/stories/story_viewer.dart';

const _video = 'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4';
const _image = 'https://flutter.github.io/assets-for-api-docs/assets/widgets/owl.jpg';
const _song = {
  'id': 5,
  'title': 'Akaneiro',
  'duration': 126,
  'audio_url': 'https://eu.data.freetouse.com/music/tracks/fc95e0bb-e942-4c4b-874b-a194fd200cf3/file/mp3/file.mp3',
  'artist': {'id': 0, 'username': '', 'display_name': 'Free To Use'},
  'source': 'freetouse',
  'source_label': 'Free To Use',
  'clip': {'start': 10, 'end': 40},
};

List<StoryGroup> _groups() => [
      StoryGroup.fromJson({
        'user': {'id': 2, 'username': 'ana', 'display_name': 'Ana'},
        'items': [
          {'id': 1, 'type': 'video', 'media_url': _video, 'mime': 'video/mp4', 'seen': true, 'song': _song},
          {'id': 2, 'type': 'image', 'media_url': _image, 'mime': 'image/jpeg', 'seen': true, 'seconds': 3, 'song': _song},
        ],
      }),
      StoryGroup.fromJson({
        'user': {'id': 3, 'username': 'luis', 'display_name': 'Luis'},
        'items': [
          {'id': 3, 'type': 'text', 'body': 'Hola', 'background': 'violet', 'seen': true, 'seconds': 2},
        ],
      }),
    ];

class _Home extends StatelessWidget {
  const _Home({required this.groups, this.initial = 0});

  final List<StoryGroup> Function() groups;
  final int initial;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => pushFade(context, StoryViewer(groups: groups(), initialGroup: initial)),
            child: const Text('Abrir historias'),
          ),
        ),
      );
}

Future<void> _wait(WidgetTester tester, int ms) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

// En la primera prueba el simulador recién arrancado puede tardar más de un segundo en mostrar el visor.
Future<void> _waitFor(WidgetTester tester, Finder finder, {int ms = 5000}) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<void> _open(WidgetTester tester, {int initial = 0}) async {
  await tester.pumpWidget(MaterialApp(home: _Home(groups: _groups, initial: initial)));
  await _wait(tester, 300);
  await tester.tap(find.text('Abrir historias'));
  await _waitFor(tester, find.byType(StoryViewer));
  await _wait(tester, 300);
  expect(find.byType(StoryViewer), findsOneWidget);
}

void _expectBackHome() {
  expect(find.byType(StoryViewer), findsNothing);
  expect(find.text('Abrir historias'), findsOneWidget);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cerrar con la X una historia de video con música', (tester) async {
    await _open(tester);
    await _wait(tester, 5000);
    await tester.tap(find.byIcon(CupertinoIcons.xmark).first);
    await _wait(tester, 2500);
    _expectBackHome();
  });

  testWidgets('cerrar deslizando hacia abajo', (tester) async {
    await _open(tester);
    await _wait(tester, 4000);
    await tester.drag(find.byType(PageView), const Offset(0, 500));
    await _wait(tester, 2500);
    _expectBackHome();
  });

  testWidgets('se cierra sola al terminar la última historia', (tester) async {
    await _open(tester, initial: 1);
    await _wait(tester, 6000);
    _expectBackHome();
  });

  testWidgets('avanzar tocando hasta el final', (tester) async {
    await _open(tester);
    final size = tester.getSize(find.byType(StoryViewer));
    for (var i = 0; i < 4; i++) {
      await _wait(tester, 1200);
      if (find.byType(StoryViewer).evaluate().isEmpty) break;
      await tester.tapAt(Offset(size.width * .8, size.height * .5));
    }
    await _wait(tester, 2500);
    _expectBackHome();
  });

  testWidgets('abrir y cerrar varias veces seguidas', (tester) async {
    await tester.pumpWidget(MaterialApp(home: _Home(groups: _groups)));
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Abrir historias'));
      await _wait(tester, 900 + i * 400);
      await tester.tap(find.byIcon(CupertinoIcons.xmark).first);
      await _wait(tester, 1200);
      _expectBackHome();
    }
  });
}
