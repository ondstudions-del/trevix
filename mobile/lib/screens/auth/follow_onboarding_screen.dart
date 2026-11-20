import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/paged.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/follow_button.dart';
import '../../widgets/paged_view.dart';
import '../../widgets/user_tile.dart';
import '../explore/suggestions_screen.dart';

/// Tras registrarse: elige a quién seguir para personalizar el Para ti.
class FollowOnboardingScreen extends StatefulWidget {
  const FollowOnboardingScreen({super.key});

  @override
  State<FollowOnboardingScreen> createState() => _FollowOnboardingScreenState();
}

class _FollowOnboardingScreenState extends State<FollowOnboardingScreen> {
  final _paged = Paged<User>('suggestions/users', User.fromJson, query: {'limit': '24'});
  final _followed = <int>{};
  bool _finishing = false;

  @override
  void dispose() {
    _paged.dispose();
    super.dispose();
  }

  Future<void> _done() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    final state = context.read<AppState>();
    await state.clearFollowOnboarding();
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AppState>().me;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Tx.bg,
        appBar: GlassBar(
          showBack: false,
          title: tr('Sigue a personas'),
          actions: [
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              onPressed: _finishing ? null : _done,
              child: Text(tr('Omitir'), style: Tx.body(15, color: Tx.muted)),
            ),
          ],
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                tr('Personaliza tu Para ti'),
                style: Tx.display(22),
              ),
              const SizedBox(height: 6),
              Text(
                tr('Sigue a quienes te interesan. Tu inicio se adapta a tus seguidos, hashtags, amigos de amigos y personas cercanas.'),
                style: Tx.body(14.5, color: Tx.muted, height: 1.4),
              ),
              if (me != null && _followed.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  tr('Siguiendo a {n}', {'n': _followed.length}),
                  style: Tx.body(13, weight: FontWeight.w700, color: Tx.accent),
                ),
              ],
            ]),
          ),
          Expanded(
            child: PagedView<User>(
              paged: _paged,
              empty: EmptyState(
                icon: CupertinoIcons.person_2,
                title: tr('Sin sugerencias por ahora'),
                message: tr('Puedes continuar y buscar personas más tarde en Explorar.'),
              ),
              itemBuilder: (context, user, i) => UserTile(
                key: ValueKey('onboard-${user.id}'),
                user: user,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  FollowButton(
                    user: user,
                    onChanged: () {
                      final following = user.relation?.following == true || user.relation?.requested == true;
                      setState(() {
                        if (following) {
                          _followed.add(user.id);
                        } else {
                          _followed.remove(user.id);
                        }
                      });
                    },
                  ),
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
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: GradientButton(
                label: _followed.isEmpty ? tr('Continuar') : tr('Listo · ir al Para ti'),
                loading: _finishing,
                onPressed: _done,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
