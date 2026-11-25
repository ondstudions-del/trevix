import '../core/api.dart';
import '../core/i18n.dart';
import '../models/models.dart';
import 'post_translation.dart';

class CommentTranslation {
  const CommentTranslation({required this.body, required this.sourceLang, required this.sameLanguage});

  final String body;
  final String sourceLang;
  final bool sameLanguage;

  String get credit => tr('Traducido del {lang} con IX', {'lang': languageName(sourceLang)});
}

Future<CommentTranslation> translateComment(int commentId, String body) async {
  if (body.trim().isEmpty) throw ApiException(422, 'empty', tr('Este comentario no tiene texto para traducir.'));
  final lang = Lang.instance.code;
  final res = (await api.post('comments/$commentId/translation', {'lang': lang})).map;
  return CommentTranslation(
    body: asStr(res['body']),
    sourceLang: asStr(res['source_lang']),
    sameLanguage: asBool(res['same_language']),
  );
}