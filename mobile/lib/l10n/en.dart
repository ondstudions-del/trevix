import 'en_account.dart';
import 'en_app.dart';
import 'en_camera.dart';
import 'en_core.dart';
import 'en_messages.dart';
import 'en_profile.dart';
import 'en_stories.dart';
import 'en_v13.dart';
import 'en_v14.dart';
import 'en_v15.dart';
import 'en_v16.dart';
import 'en_v17.dart';
import 'en_v18.dart';
import 'en_v19.dart';
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
  ...enV15,
  ...enV16,
  ...enV17,
  ...enV18,
  ...enV19,
};
