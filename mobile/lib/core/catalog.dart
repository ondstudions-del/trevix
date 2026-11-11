// Catálogos que también valida el servidor (app/Models/*.php). Se usan para llenar los selectores.
// Las etiquetas se traducen al leerlas (getters), así que no pueden usarse en contextos const.

import 'i18n.dart';

Map<String, String> get feedTabs => {'foryou': tr('Para ti'), 'following': tr('Siguiendo'), 'friends': tr('Amigos'), 'trending': tr('Tendencias')};

Map<String, String> get visibilities => {'public': tr('Público'), 'followers': tr('Seguidores'), 'private': tr('Solo yo')};

Map<String, String> get reportReasons => {
      'spam': tr('Spam o publicidad engañosa'),
      'harassment': tr('Acoso o intimidación'),
      'hate': tr('Discurso de odio'),
      'violence': tr('Violencia o amenazas'),
      'nudity': tr('Desnudos o contenido sexual'),
      'misinformation': tr('Información falsa'),
      'impersonation': tr('Suplantación de identidad'),
      'self_harm': tr('Autolesiones o suicidio'),
      'other': tr('Otro motivo'),
    };

/// Los valores se envían tal cual al servidor: se traducen solo al mostrarlos (`tr(categoría)`).
const communityCategories = [
  'Arte', 'Ciencia', 'Deportes', 'Diseño', 'Educación', 'Entretenimiento', 'Estilo de vida',
  'Fotografía', 'Gaming', 'Música', 'Negocios', 'Tecnología', 'Viajes', 'Otra',
];

Map<String, String> get accountTypes => {'personal': tr('Cuenta normal'), 'creator': tr('Creador de contenido')};

Map<String, String> get creatorCategories => {
      'music_artist': tr('Artista musical'),
      'influencer': tr('Influencer'),
      'blogger': tr('Blogger'),
      'other': tr('Otro'),
    };

Map<String, String> get messagePrivacy => {
      'everyone': tr('Todos'),
      'following': tr('Personas que sigo'),
      'nobody': tr('Nadie'),
    };

Map<String, String> get songGenres => {
      'pop': tr('Pop'),
      'rock': tr('Rock'),
      'hiphop': tr('Hip hop / Rap'),
      'reggaeton': tr('Reguetón / Urbano'),
      'latin': tr('Latina / Tropical'),
      'electronic': tr('Electrónica'),
      'rnb': tr('R&B / Soul'),
      'indie': tr('Indie / Alternativa'),
      'jazz': tr('Jazz / Blues'),
      'classical': tr('Clásica / Instrumental'),
      'regional': tr('Regional / Folclor'),
      'other': tr('Otro'),
    };

Map<String, String> get songStatuses => {
      'all': tr('Todas'),
      'pending': tr('En revisión'),
      'published': tr('Publicadas'),
      'rejected': tr('Rechazadas'),
      'withdrawn': tr('Retiradas'),
      'removed': tr('Por moderación'),
      'cancelled': tr('Canceladas'),
    };

Map<String, String> get storyBackgrounds => {
      'violet': tr('Violeta'),
      'blue': tr('Azul'),
      'midnight': tr('Medianoche'),
      'sunset': tr('Atardecer'),
      'ocean': tr('Océano'),
      'graphite': tr('Grafito'),
    };
