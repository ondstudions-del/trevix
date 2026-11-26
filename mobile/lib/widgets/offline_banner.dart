import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/network.dart';
import '../core/theme.dart';

/// Franja «Offline» fija arriba; desaparece al recuperar Internet.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: NetworkStatus.instance,
      builder: (context, _) {
        final offline = !NetworkStatus.instance.online;
        return Stack(
          children: [
            child,
            if (offline)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Material(
                  color: Tx.alpha(Colors.black, .9),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(CupertinoIcons.wifi_slash, size: 16, color: Colors.white70),
                          const SizedBox(width: 8),
                          Text(tr('Offline'), style: Tx.body(13.5, weight: FontWeight.w700, color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}