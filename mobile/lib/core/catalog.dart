// Catálogos que también valida el servidor (app/Models/*.php). Se usan para llenar los selectores.

const feedTabs = {'foryou': 'Para ti', 'following': 'Siguiendo', 'friends': 'Amigos', 'trending': 'Tendencias'};

const visibilities = {'public': 'Público', 'followers': 'Seguidores', 'private': 'Solo yo'};

const reportReasons = {
  'spam': 'Spam o publicidad engañosa',
  'harassment': 'Acoso o intimidación',
  'hate': 'Discurso de odio',
  'violence': 'Violencia o amenazas',
  'nudity': 'Desnudos o contenido sexual',
  'misinformation': 'Información falsa',
  'impersonation': 'Suplantación de identidad',
  'self_harm': 'Autolesiones o suicidio',
  'other': 'Otro motivo',
};

const communityCategories = [
  'Arte', 'Ciencia', 'Deportes', 'Diseño', 'Educación', 'Entretenimiento', 'Estilo de vida',
  'Fotografía', 'Gaming', 'Música', 'Negocios', 'Tecnología', 'Viajes', 'Otra',
];

const accountTypes = {'personal': 'Cuenta normal', 'creator': 'Creador de contenido'};

const creatorCategories = {
  'music_artist': 'Artista musical',
  'influencer': 'Influencer',
  'blogger': 'Blogger',
  'other': 'Otro',
};

const messagePrivacy = {
  'everyone': 'Todos',
  'following': 'Personas que sigo',
  'nobody': 'Nadie',
};

const songGenres = {
  'pop': 'Pop',
  'rock': 'Rock',
  'hiphop': 'Hip hop / Rap',
  'reggaeton': 'Reguetón / Urbano',
  'latin': 'Latina / Tropical',
  'electronic': 'Electrónica',
  'rnb': 'R&B / Soul',
  'indie': 'Indie / Alternativa',
  'jazz': 'Jazz / Blues',
  'classical': 'Clásica / Instrumental',
  'regional': 'Regional / Folclor',
  'other': 'Otro',
};

const songStatuses = {
  'all': 'Todas',
  'pending': 'En revisión',
  'published': 'Publicadas',
  'rejected': 'Rechazadas',
  'withdrawn': 'Retiradas',
  'removed': 'Por moderación',
  'cancelled': 'Canceladas',
};

const storyBackgrounds = {
  'violet': 'Violeta',
  'blue': 'Azul',
  'midnight': 'Medianoche',
  'sunset': 'Atardecer',
  'ocean': 'Océano',
  'graphite': 'Grafito',
};
