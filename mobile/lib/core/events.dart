import 'package:flutter/foundation.dart';

import '../models/models.dart';

/// Publicación recién creada desde cualquier pantalla (el inicio y el perfil la insertan arriba).
final postCreated = ValueNotifier<Post?>(null);

/// Se publicó o eliminó una historia propia (la barra de historias se recarga).
final storiesChanged = ValueNotifier<int>(0);

/// Se publicó o eliminó la nota propia (la barra de historias y el perfil se recargan).
final notesChanged = ValueNotifier<int>(0);

/// Pestaña del inicio que debe mostrarse (un aviso del teléfono abre la de notificaciones). -1 = ninguna.
final homeTabRequest = ValueNotifier<int>(-1);
