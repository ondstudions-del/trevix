import 'package:flutter/foundation.dart';

import '../models/models.dart';

/// Publicación recién creada desde cualquier pantalla (el inicio y el perfil la insertan arriba).
final postCreated = ValueNotifier<Post?>(null);

/// Se publicó o eliminó una historia propia (la barra de historias se recarga).
final storiesChanged = ValueNotifier<int>(0);
