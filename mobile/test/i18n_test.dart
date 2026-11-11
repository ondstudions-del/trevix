import 'package:flutter_test/flutter_test.dart';
import 'package:trevix/core/format.dart';
import 'package:trevix/core/i18n.dart';
import 'package:trevix/l10n/en.dart';
import 'package:trevix/screens/browser/browser_screen.dart';
import 'package:trevix/widgets/post_translation.dart';

void main() {
  tearDown(() => Lang.instance.code = 'es');

  test('tr devuelve el español o su traducción y reemplaza los argumentos', () {
    expect(tr('Ver traducción'), 'Ver traducción');
    expect(tr('Abrir {site}', {'site': 'x.com'}), 'Abrir x.com');
    Lang.instance.code = 'en';
    expect(tr('Ver traducción'), 'See translation');
    expect(tr('Abrir {site}', {'site': 'x.com'}), 'Open x.com');
    expect(tr('Texto sin traducción'), 'Texto sin traducción');
  });

  test('las traducciones conservan los marcadores {…}', () {
    final marker = RegExp(r'\{(\w+)\}');
    for (final e in en.entries) {
      final want = marker.allMatches(e.key).map((m) => m[1]).toSet();
      final got = marker.allMatches(e.value).map((m) => m[1]).toSet();
      expect(got, want, reason: '«${e.key}» → «${e.value}»');
    }
  });

  test('números, fechas y plurales según el idioma', () {
    expect(compact(1500), '1,5 mil');
    expect(birthday(14, 3, 1998), '14 de marzo de 1998');
    expect(plural(2, 'vista', 'vistas'), '2 vistas');
    Lang.instance.code = 'en';
    expect(compact(1500), '1.5K');
    expect(compact(3400000), '3.4M');
    expect(birthday(14, 3, 1998), 'March 14, 1998');
    expect(plural(1, 'vista', 'vistas'), '1 view');
  });

  test('la barra del navegador distingue direcciones de búsquedas', () {
    expect(looksLikeUrl('google.com'), isTrue);
    expect(looksLikeUrl('www.x.co/a?b=1'), isTrue);
    expect(looksLikeUrl('https://trevix.ond-s.com/post.php?id=5'), isTrue);
    expect(looksLikeUrl('recetas de arepas'), isFalse);
    expect(looksLikeUrl('hola'), isFalse);
    expect(looksLikeUrl('juan@gmail.com'), isFalse);
    expect(browserTarget('google.com').toString(), 'https://google.com');
    expect(browserTarget('arepas').host, 'www.google.com');
  });

  test('idioma probable de una publicación', () {
    expect(guessLanguage('Hoy fue un día increíble con mis amigos en la playa'), 'es');
    expect(guessLanguage('This is the best day of my life with all my friends'), 'en');
    expect(guessLanguage('🔥🔥'), isNull);
    expect(offerTranslation('This is the best day of my life with all my friends'), isTrue);
    expect(offerTranslation('Hoy fue un día increíble con mis amigos en la playa'), isFalse);
  });
}
