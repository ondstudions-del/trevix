import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/appearance.dart';
import 'core/deeplinks.dart';
import 'core/session.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DeepLinks.instance.install();
  await Appearance.instance.load();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  if (Platform.isAndroid) {
    // De borde a borde como en el iPhone: barras del sistema transparentes sobre el fondo de la app.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  SystemChrome.setSystemUIOverlayStyle(Tx.overlay);
  runApp(ChangeNotifierProvider(create: (_) => AppState()..start(), child: const TrevixApp()));
}
