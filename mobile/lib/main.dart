import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/deeplinks.dart';
import 'core/session.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  DeepLinks.instance.install();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  if (Platform.isAndroid) {
    // De borde a borde como en el iPhone: barras del sistema transparentes sobre el fondo oscuro de la app.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
    ));
  }
  runApp(ChangeNotifierProvider(create: (_) => AppState()..start(), child: const TrevixApp()));
}
