import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/follow_button.dart';
import '../../widgets/paged_view.dart';
import '../../widgets/user_tile.dart';

/// Quita a una persona de las sugerencias («No me interesa», 90 días). Devuelve true si se quitó.
Future<bool> dismissSuggestion(BuildContext context, User user) async {
  try {
    final res = await api.post('suggestions/users/${user.id}/dismiss');
    if (context.mounted) toast(context, '${res.map['message'] ?? tr('Listo.')}');
    return true;
  } catch (e) {
    if (context.mounted) toastError(context, e);
    return false;
  }
}

/// Personas que quizá conozcas: te siguen, amigos en común, misma ciudad, interacciones e intereses.
class SuggestionsScreen extends StatefulWidget {
  const SuggestionsScreen({super.key});

  @override
  State<SuggestionsScreen> createState() => _SuggestionsScreenState();
}

class _SuggestionsScreenState extends State<SuggestionsScreen> {
  final _paged = Paged<User>('suggestions/users', User.fromJson, query: {'limit': '20'});

  @override
  void dispose() {
    _paged.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassBar(title: tr('Personas que quizá conozcas')),
      body: PagedView<User>(
        paged: _paged,
        header: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
              child: Text(
                tr('Te las sugerimos por amigos en común, tu ciudad, las personas con las que interactúas y tus intereses. Añade tu ciudad e intereses en Editar perfil → Datos personales para ver a quienes tienes más cerca.'),
                style: Tx.body(13, color: Tx.muted, height: 1.4),
              ),
            ),
          ),
        ],
        empty: EmptyState(
          icon: CupertinoIcons.person_2,
          title: tr('Sin sugerencias por ahora'),
          message: tr('Sigue a más personas o completa tus datos personales para recibir sugerencias.'),
        ),
        itemBuilder: (context, user, i) => UserTile(
          key: ValueKey('suggestion-${user.id}'),
          user: user,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            FollowButton(user: user),
            IconButton(
              tooltip: tr('No me interesa'),
              icon: Icon(CupertinoIcons.xmark, size: 18, color: Tx.subtle),
              onPressed: () async {
                if (await dismissSuggestion(context, user)) _paged.remove((u) => u.id == user.id);
              },
            ),
          ]),
        ),
      ),
    );
  }
}
