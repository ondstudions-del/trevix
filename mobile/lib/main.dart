import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/appearance.dart';
import 'core/deeplinks.dart';
import 'core/device.dart';
import 'core/i18n.dart';
import 'core/session.dart';
import 'core/share_in.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DeepLinks.instance.install();
  ShareIn.install();
  await Appearance.instance.load();
  await Lang.instance.load();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  if (Platform.isAndroid) {
    // De borde a borde como en el iPhone: barras del sistema transparentes sobre el fondo de la app.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  SystemChrome.setSystemUIOverlayStyle(Tx.overlay);
  unawaited(DeviceAccess.installSounds());
  runApp(ChangeNotifierProvider(create: (_) => AppState()..start(), child: const TrevixApp()));
}
