import '../core/api.dart';
import '../core/i18n.dart';
import '../models/models.dart';

/// Traducción del texto de una publicación hecha por IX en el servidor.
class PostTranslation {
  const PostTranslation({required this.body, required this.sourceLang, required this.sameLanguage});

  final String body;
  final String sourceLang;
  final bool sameLanguage;

  /// «Traducido del inglés con IX».
  String get credit => tr('Traducido del {lang} con IX', {'lang': languageName(sourceLang)});
}

const _names = {
  'es': 'español',
  'en': 'inglés',
  'pt': 'portugués',
  'fr': 'francés',
  'it': 'italiano',
  'de': 'alemán',
  'ca': 'catalán',
  'nl': 'neerlandés',
  'ja': 'japonés',
  'ko': 'coreano',
  'zh': 'chino',
  'ar': 'árabe',
  'ru': 'ruso',
};

String languageName(String code) {
  final name = _names[code.toLowerCase()];
  return name == null ? code.toUpperCase() : tr(name);
}

/// Traducciones ya pedidas en esta sesión (por publicación, idioma y texto) para no repetir la llamada.
final _cache = <String, PostTranslation>{};

Future<PostTranslation> translatePost(int postId, String body) async {
  final lang = Lang.instance.code;
  final key = '$postId:$lang:${body.hashCode}';
  final cached = _cache[key];
  if (cached != null) return cached;
  final res = (await api.post('posts/$postId/translation', {'lang': lang})).map;
  final t = PostTranslation(
    body: asStr(res['body']),
    sourceLang: asStr(res['source_lang']),
    sameLanguage: asBool(res['same_language']),
  );
  _cache[key] = t;
  return t;
}

const _es = {
  'el', 'la', 'los', 'las', 'de', 'del', 'que', 'y', 'en', 'un', 'una', 'por', 'para', 'con', 'no', 'es', 'se', 'lo',
  'mi', 'tu', 'su', 'al', 'como', 'pero', 'más', 'muy', 'hoy', 'todo', 'gracias', 'hola', 'este', 'esta', 'yo', 'ya',
  'qué', 'cuando', 'donde', 'porque', 'también', 'son', 'está', 'estoy', 'fue', 'ser', 'hay', 'nos', 'les', 'sin',
};
const _en = {
  'the', 'and', 'of', 'to', 'is', 'in', 'it', 'you', 'that', 'for', 'on', 'with', 'this', 'my', 'are', 'was', 'be',
  'have', 'not', 'but', 'at', 'so', 'we', 'they', 'what', 'all', 'just', 'your', 'from', 'today', 'thanks', 'love',
  'can', 'will', 'me', 'our', 'about', 'when', 'there', 'one', 'more', 'like', 'i\'m', 'it\'s', 'don\'t', 'very',
};

/// Idioma probable de un texto ('es', 'en', 'other') o null si es muy corto o dudoso. Solo decide si en el feed se
/// ofrece «Ver traducción»; el idioma real lo detecta IX al traducir.
String? guessLanguage(String text) {
  final words = RegExp(r"[\p{L}']+", unicode: true).allMatches(text.toLowerCase()).map((m) => m[0]!).toList();
  if (words.length < 3) return null;
  var es = 0, en = 0;
  for (final w in words) {
    if (_es.contains(w)) es++;
    if (_en.contains(w)) en++;
  }
  if (RegExp('[ñ¿¡áéíóú]').hasMatch(text.toLowerCase())) es += 2;
  if (es + en < 2) {
    // Muchas palabras y ninguna común del español ni del inglés: otro idioma (si usa letras).
    return words.length >= 6 ? 'other' : null;
  }
  if (es >= en * 2) return 'es';
  if (en >= es * 2) return 'en';
  return null;
}

/// ¿Ofrecer la traducción en el feed? Cuando el texto parece estar en otro idioma que el de la app.
bool offerTranslation(String text) {
  final guess = guessLanguage(text);
  return guess != null && guess != Lang.instance.code;
}
