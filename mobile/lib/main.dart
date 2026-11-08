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
  runApp(ChangeNotifierProvider(create: (_) => AppState()..start(), child: const TrevixApp()));
}
