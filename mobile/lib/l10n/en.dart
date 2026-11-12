import 'en_account.dart';
import 'en_app.dart';
import 'en_camera.dart';
import 'en_core.dart';
import 'en_messages.dart';
import 'en_profile.dart';
import 'en_stories.dart';
import 'en_v13.dart';
import 'en_v14.dart';
import 'en_wallet.dart';

/// Inglés: texto en español tal como está en el código → traducción. Un archivo por área de la app.
final Map<String, String> en = {
  ...enCore,
  ...enApp,
  ...enAccount,
  ...enMessages,
  ...enProfile,
  ...enStories,
  ...enWallet,
  ...enCamera,
  ...enV13,
  ...enV14,
};
