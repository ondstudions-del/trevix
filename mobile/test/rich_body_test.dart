import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trevix/widgets/format_bar.dart';
import 'package:trevix/widgets/rich_body.dart';

void main() {
  test('negrita, cursiva y viñetas como las muestra la web', () {
    final (text, marks) = parseMarks('Hola **mundo** y *todos*\n- uno\n* dos');
    expect(text, 'Hola mundo y todos\n• uno\n• dos');
    expect(marks.where((m) => m.bold).map((m) => text.substring(m.start, m.end)), ['mundo']);
    expect(marks.where((m) => !m.bold).map((m) => text.substring(m.start, m.end)), ['todos']);
  });

  test('las marcas se ajustan al quitar las de otra clase', () {
    final (text, marks) = parseMarks('*a* **bc** *d*');
    expect(text, 'a bc d');
    final bold = marks.firstWhere((m) => m.bold);
    expect(text.substring(bold.start, bold.end), 'bc');
    expect(marks.where((m) => !m.bold).map((m) => text.substring(m.start, m.end)), ['a', 'd']);
  });

  test('no toca asteriscos sueltos, multiplicaciones ni guiones', () {
    expect(plainText('2 * 3 = 6'), '2 * 3 = 6');
    expect(plainText('a*b*c'), 'a*b*c');
    expect(plainText('** nada **'), '** nada **');
    expect(plainText('-5 grados'), '-5 grados');
    expect(plainText('@ana_maria escribe'), '@ana_maria escribe');
  });

  testWidgets('la barra envuelve la selección y continúa las viñetas', (tester) async {
    final c = TextEditingController(text: 'hola mundo');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: FormatBar(controller: c))));
    c.selection = const TextSelection(baseOffset: 5, extentOffset: 10);
    await tester.tap(find.text('B'));
    expect(c.text, 'hola **mundo**');
    await tester.tap(find.text('B'));
    expect(c.text, 'hola mundo');

    c.value = const TextEditingValue(text: '• uno', selection: TextSelection.collapsed(offset: 5));
    c.value = const TextEditingValue(text: '• uno\n', selection: TextSelection.collapsed(offset: 6));
    expect(c.text, '• uno\n• ');
    c.value = const TextEditingValue(text: '• uno\n• \n', selection: TextSelection.collapsed(offset: 9));
    expect(c.text, '• uno\n');
    c.dispose();
  });
}
