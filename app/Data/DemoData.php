<?php
declare(strict_types=1);

namespace Trevix\Data;

/**
 * Contenido de demostración para el modo vista previa (Fase 1).
 *
 * Solo lo usan los controladores cuando Config::previewEnabled() es verdadero y no hay
 * sesión real. Las estructuras replican las columnas de trevix_db para que los modelos
 * reales las sustituyan sin tocar las vistas.
 */
final class DemoData
{
    private static ?array $users = null;

    private static function ago(int $minutes): string
    {
        return date('Y-m-d H:i:s', time() - $minutes * 60);
    }

    public static function users(): array
    {
        if (self::$users !== null) {
            return self::$users;
        }

        $base = [
            'avatar_path' => null, 'cover_path' => null, 'is_private' => false, 'is_verified' => false,
            'role' => 'user', 'website' => null, 'relationship' => 'none',
        ];

        $list = [
            ['id' => 1, 'username' => 'valentina.rios', 'display_name' => 'Valentina Ríos', 'role' => 'admin',
                'bio' => 'Product designer. Construyendo experiencias digitales con intención. Café, tipografía y fotografía analógica.',
                'country' => 'Colombia', 'website' => 'https://valentinarios.design', 'cover_art' => 'aurora',
                'followers_count' => 2841, 'following_count' => 386, 'posts_count' => 214, 'created_at' => '2025-03-14 10:00:00'],
            ['id' => 2, 'username' => 'mateo.dev', 'display_name' => 'Mateo Herrera', 'is_verified' => true, 'relationship' => 'friend',
                'bio' => 'Ingeniero de software. PHP, sistemas distribuidos y código limpio. Escribo hilos sobre arquitectura.',
                'country' => 'México', 'cover_art' => 'horizon',
                'followers_count' => 18420, 'following_count' => 512, 'posts_count' => 1289, 'created_at' => '2024-11-02 09:00:00'],
            ['id' => 3, 'username' => 'luciana.foto', 'display_name' => 'Luciana Paredes', 'is_verified' => true, 'relationship' => 'following',
                'bio' => 'Fotógrafa de paisajes. La luz lo es todo. Patagonia · Andes · Atacama.',
                'country' => 'Chile', 'cover_art' => 'peaks',
                'followers_count' => 96300, 'following_count' => 245, 'posts_count' => 842, 'created_at' => '2024-08-21 09:00:00'],
            ['id' => 4, 'username' => 'nico.design', 'display_name' => 'Nicolás Vega', 'relationship' => 'friend',
                'bio' => 'UI designer y motion. Explorando el futuro de las interfaces.',
                'country' => 'Argentina', 'cover_art' => 'orbs',
                'followers_count' => 7210, 'following_count' => 690, 'posts_count' => 431, 'created_at' => '2025-01-10 09:00:00'],
            ['id' => 5, 'username' => 'sofia.travel', 'display_name' => 'Sofía Martínez', 'relationship' => 'following',
                'bio' => 'Viajo, escribo y lo comparto todo. 42 países y contando.',
                'country' => 'España', 'cover_art' => 'city',
                'followers_count' => 31870, 'following_count' => 1020, 'posts_count' => 1544, 'created_at' => '2024-06-05 09:00:00'],
            ['id' => 6, 'username' => 'andres.music', 'display_name' => 'Andrés Ruiz',
                'bio' => 'Productor musical. Sintetizadores, beats y madrugadas de estudio.',
                'country' => 'Perú', 'cover_art' => 'waves',
                'followers_count' => 12450, 'following_count' => 310, 'posts_count' => 602, 'created_at' => '2025-02-18 09:00:00'],
            ['id' => 7, 'username' => 'camila.lab', 'display_name' => 'Camila Torres', 'is_verified' => true, 'relationship' => 'friend',
                'bio' => 'Bióloga e investigadora. Divulgación científica sin complicaciones.',
                'country' => 'Uruguay', 'cover_art' => 'aurora',
                'followers_count' => 45120, 'following_count' => 402, 'posts_count' => 978, 'created_at' => '2024-09-30 09:00:00'],
            ['id' => 8, 'username' => 'diego.runs', 'display_name' => 'Diego Castillo', 'is_private' => true,
                'bio' => 'Corredor de montaña. Entrenando para mi primer ultra.',
                'country' => 'Ecuador', 'cover_art' => 'peaks',
                'followers_count' => 864, 'following_count' => 455, 'posts_count' => 97, 'created_at' => '2025-05-12 09:00:00'],
            ['id' => 9, 'username' => 'isa.reads', 'display_name' => 'Isabella Gómez', 'relationship' => 'following',
                'bio' => 'Lectora compulsiva. Reseñas honestas y recomendaciones semanales.',
                'country' => 'Colombia', 'cover_art' => 'orbs',
                'followers_count' => 5630, 'following_count' => 780, 'posts_count' => 352, 'created_at' => '2025-04-01 09:00:00'],
            ['id' => 10, 'username' => 'trevix', 'display_name' => 'TREVIX', 'is_verified' => true, 'relationship' => 'following',
                'bio' => 'Cuenta oficial de TREVIX. Novedades, consejos y anuncios de la plataforma.',
                'country' => 'Global', 'cover_art' => 'horizon',
                'followers_count' => 250000, 'following_count' => 12, 'posts_count' => 87, 'created_at' => '2024-01-01 09:00:00'],
        ];

        self::$users = [];
        foreach ($list as $user) {
            self::$users[$user['username']] = array_merge($base, $user);
        }
        return self::$users;
    }

    public static function user(string $username): ?array
    {
        return self::users()[$username] ?? null;
    }

    public static function viewer(): array
    {
        return self::user('valentina.rios') + ['unread_notifications' => 4, 'unread_messages' => 2];
    }

    private static function media(string $art, string $alt): array
    {
        return ['type' => 'image', 'src' => 'assets/img/demo/' . $art . '.svg', 'alt' => $alt];
    }

    public static function posts(): array
    {
        $u = self::users();

        $original = [
            'id' => 101, 'user' => $u['luciana.foto'], 'format' => 'post',
            'body' => "Amanecer a 4.200 metros. Esperé tres noches por esta luz y valió cada minuto de frío.\n\nCuéntenme: ¿madrugarían por una foto así? #Fotografía #Patagonia",
            'media' => [self::media('aurora', 'Auroras violetas y azules sobre una cordillera al amanecer')],
            'community' => null, 'shared' => null, 'created_at' => self::ago(38),
            'likes_count' => 4821, 'comments_count' => 312, 'shares_count' => 140, 'saves_count' => 980,
            'viewer_liked' => true, 'viewer_saved' => false, 'is_edited' => false, 'replies' => [],
            'feeds' => ['foryou', 'following', 'trending'],
        ];

        return [
            $original,
            [
                'id' => 102, 'user' => $u['mateo.dev'], 'format' => 'thread',
                'body' => "Hilo: 5 decisiones de arquitectura que ojalá hubiera tomado desde el día uno en un proyecto PHP.\n\n1. Separar controladores, modelos y vistas aunque el proyecto sea pequeño.\n2. PDO con sentencias preparadas, siempre.\n3. Tokens CSRF en cada formulario que modifique datos.\n\nContinúa en las respuestas. #PHP #Arquitectura",
                'media' => [], 'community' => null, 'shared' => null, 'created_at' => self::ago(72),
                'likes_count' => 1290, 'comments_count' => 184, 'shares_count' => 402, 'saves_count' => 1310,
                'viewer_liked' => false, 'viewer_saved' => true, 'is_edited' => true,
                'replies' => [
                    ['user' => $u['mateo.dev'], 'body' => '4. Validar en el servidor. La validación en JavaScript es experiencia de usuario, no seguridad.', 'created_at' => self::ago(70), 'likes_count' => 402],
                    ['user' => $u['nico.design'], 'body' => 'El punto 4 debería estar tatuado en cada equipo. Gran hilo, @mateo.dev', 'created_at' => self::ago(55), 'likes_count' => 88],
                ],
                'feeds' => ['foryou', 'following', 'friends', 'trending'],
            ],
            [
                'id' => 103, 'user' => $u['nico.design'], 'format' => 'post',
                'body' => 'Exploraciones de interfaz para un sistema de diseño oscuro. Luz sutil, profundidad y mucho espacio negativo. ¿Cuál prefieren? #DiseñoUI',
                'media' => [
                    self::media('horizon', 'Horizonte con cuadrícula en perspectiva y sol violeta'),
                    self::media('orbs', 'Esferas luminosas moradas y azules flotando'),
                    self::media('waves', 'Ondas de luz azul y violeta sobre fondo negro'),
                ],
                'community' => ['slug' => 'diseno-ui', 'name' => 'Diseño UI/UX'], 'shared' => null, 'created_at' => self::ago(140),
                'likes_count' => 862, 'comments_count' => 97, 'shares_count' => 31, 'saves_count' => 240,
                'viewer_liked' => false, 'viewer_saved' => false, 'is_edited' => false, 'replies' => [],
                'feeds' => ['foryou', 'following', 'friends'],
            ],
            [
                'id' => 104, 'user' => $u['camila.lab'], 'format' => 'thread',
                'body' => 'Pregunta abierta para docentes y estudiantes: ¿la inteligencia artificial en el aula está ayudando a aprender o solo a entregar tareas más rápido? Quiero leer experiencias reales. #Educación #IA',
                'media' => [], 'community' => null, 'shared' => null, 'created_at' => self::ago(210),
                'likes_count' => 2310, 'comments_count' => 645, 'shares_count' => 290, 'saves_count' => 410,
                'viewer_liked' => true, 'viewer_saved' => false, 'is_edited' => false,
                'replies' => [
                    ['user' => $u['isa.reads'], 'body' => 'Como estudiante: me ayuda a entender temas difíciles, pero solo cuando la uso para preguntar, no para copiar.', 'created_at' => self::ago(190), 'likes_count' => 310],
                ],
                'feeds' => ['foryou', 'friends', 'trending'],
            ],
            [
                'id' => 105, 'user' => $u['sofia.travel'], 'format' => 'post',
                'body' => 'De la ciudad que nunca duerme a montañas donde no llega la señal. Dos caras del mismo viaje. #Viajes',
                'media' => [
                    self::media('city', 'Ciudad nocturna con luces de neón violetas'),
                    self::media('peaks', 'Picos montañosos bajo un cielo azul degradado'),
                ],
                'community' => null, 'shared' => null, 'created_at' => self::ago(320),
                'likes_count' => 3104, 'comments_count' => 128, 'shares_count' => 76, 'saves_count' => 512,
                'viewer_liked' => false, 'viewer_saved' => true, 'is_edited' => false, 'replies' => [],
                'feeds' => ['foryou', 'following'],
            ],
            [
                'id' => 106, 'user' => $u['andres.music'], 'format' => 'post',
                'body' => 'Esta foto me inspiró el intro del próximo track. Paisaje sonoro grabado a las 4 a. m. Gracias @luciana.foto',
                'media' => [], 'community' => null, 'shared' => $original, 'created_at' => self::ago(400),
                'likes_count' => 540, 'comments_count' => 42, 'shares_count' => 12, 'saves_count' => 60,
                'viewer_liked' => false, 'viewer_saved' => false, 'is_edited' => false, 'replies' => [],
                'feeds' => ['foryou'],
            ],
            [
                'id' => 107, 'user' => $u['isa.reads'], 'format' => 'thread',
                'body' => "Reto de noviembre en el club: un libro latinoamericano escrito en los últimos cinco años.\n\nDejen su recomendación y armamos la lista colectiva.",
                'media' => [], 'community' => ['slug' => 'club-de-lectura', 'name' => 'Club de Lectura'], 'shared' => null,
                'created_at' => self::ago(560),
                'likes_count' => 318, 'comments_count' => 156, 'shares_count' => 22, 'saves_count' => 95,
                'viewer_liked' => false, 'viewer_saved' => false, 'is_edited' => false, 'replies' => [],
                'feeds' => ['foryou', 'following'],
            ],
            [
                'id' => 108, 'user' => $u['trevix'], 'format' => 'post',
                'body' => 'Bienvenida a TREVIX: un solo lugar para tus fotos, tus ideas y tus comunidades. Así se ve la nueva generación de redes sociales. #TREVIX',
                'media' => [
                    self::media('orbs', 'Composición abstracta de esferas luminosas'),
                    self::media('aurora', 'Aurora violeta sobre montañas'),
                    self::media('city', 'Ciudad con luces de neón'),
                    self::media('waves', 'Ondas luminosas'),
                ],
                'community' => null, 'shared' => null, 'created_at' => self::ago(1500),
                'likes_count' => 18340, 'comments_count' => 1204, 'shares_count' => 3410, 'saves_count' => 2200,
                'viewer_liked' => true, 'viewer_saved' => false, 'is_edited' => false, 'replies' => [],
                'feeds' => ['foryou', 'following', 'trending'],
            ],
        ];
    }

    public static function postsByUser(string $username): array
    {
        return array_values(array_filter(self::posts(), static fn (array $p) => $p['user']['username'] === $username));
    }

    public static function stories(): array
    {
        $u = self::users();
        $s = static fn (string $type, string $value, string $caption = '') => [
            'id' => 0, 'type' => $type, 'src' => $type === 'image' ? 'assets/img/demo/' . $value . '.svg' : null,
            'background' => $type === 'text' ? $value : null, 'body' => $caption, 'seconds' => 6, 'views' => 0,
            'seen' => false, 'created_at' => self::ago(60),
        ];

        return [
            ['user' => $u['luciana.foto'], 'seen' => false, 'created_at' => self::ago(50), 'items' => [
                $s('image', 'aurora', 'Tercera noche de espera'),
                $s('image', 'peaks', 'Y por fin, la luz'),
            ]],
            ['user' => $u['mateo.dev'], 'seen' => false, 'created_at' => self::ago(95), 'items' => [
                $s('text', 'violet', 'Nuevo hilo sobre arquitectura PHP en mi perfil'),
            ]],
            ['user' => $u['nico.design'], 'seen' => false, 'created_at' => self::ago(180), 'items' => [
                $s('image', 'orbs', 'Work in progress'),
                $s('image', 'horizon', 'Versión final'),
            ]],
            ['user' => $u['sofia.travel'], 'seen' => false, 'created_at' => self::ago(260), 'items' => [
                $s('image', 'city', 'Primera noche en la ciudad'),
            ]],
            ['user' => $u['andres.music'], 'seen' => true, 'created_at' => self::ago(420), 'items' => [
                $s('text', 'blue', 'Track nuevo este viernes'),
            ]],
            ['user' => $u['camila.lab'], 'seen' => true, 'created_at' => self::ago(700), 'items' => [
                $s('text', 'midnight', 'Mañana: transmisión sobre biodiversidad marina'),
            ]],
        ];
    }

    public static function trends(): array
    {
        return [
            ['tag' => 'Fotografía', 'category' => 'Arte · Tendencia', 'posts_count' => 48200],
            ['tag' => 'PHP', 'category' => 'Tecnología', 'posts_count' => 12900],
            ['tag' => 'IA', 'category' => 'Tecnología · Tendencia', 'posts_count' => 95100],
            ['tag' => 'DiseñoUI', 'category' => 'Diseño', 'posts_count' => 8700],
            ['tag' => 'Viajes', 'category' => 'Estilo de vida', 'posts_count' => 31400],
            ['tag' => 'Educación', 'category' => 'Sociedad', 'posts_count' => 6200],
        ];
    }

    public static function suggestions(): array
    {
        $u = self::users();
        return [
            $u['camila.lab'] + ['reason' => 'Te sigue'],
            $u['andres.music'] + ['reason' => 'Seguido por Nicolás Vega'],
            $u['diego.runs'] + ['reason' => 'Nuevo en TREVIX'],
        ];
    }

    public static function communities(): array
    {
        return [
            ['id' => 1, 'slug' => 'diseno-ui', 'name' => 'Diseño UI/UX', 'description' => 'Interfaces, sistemas de diseño, prototipos y crítica constructiva.',
                'visibility' => 'public', 'members_count' => 24800, 'posts_count' => 5120, 'art' => 'orbs', 'is_member' => true, 'category' => 'Diseño'],
            ['id' => 2, 'slug' => 'fotografia-nocturna', 'name' => 'Fotografía Nocturna', 'description' => 'Astrofotografía, larga exposición y ciudades de noche.',
                'visibility' => 'public', 'members_count' => 18300, 'posts_count' => 9400, 'art' => 'aurora', 'is_member' => true, 'category' => 'Fotografía'],
            ['id' => 3, 'slug' => 'dev-latam', 'name' => 'Dev Latam', 'description' => 'Desarrolladores de Latinoamérica compartiendo código, empleo y aprendizaje.',
                'visibility' => 'public', 'members_count' => 61200, 'posts_count' => 22800, 'art' => 'horizon', 'is_member' => false, 'category' => 'Tecnología'],
            ['id' => 4, 'slug' => 'club-de-lectura', 'name' => 'Club de Lectura', 'description' => 'Un libro al mes, debates semanales y recomendaciones honestas.',
                'visibility' => 'public', 'members_count' => 9100, 'posts_count' => 3300, 'art' => 'peaks', 'is_member' => true, 'category' => 'Cultura'],
            ['id' => 5, 'slug' => 'viajeros', 'name' => 'Viajeros', 'description' => 'Rutas, consejos y destinos fuera del radar turístico.',
                'visibility' => 'public', 'members_count' => 40500, 'posts_count' => 14100, 'art' => 'city', 'is_member' => false, 'category' => 'Estilo de vida'],
            ['id' => 6, 'slug' => 'productores', 'name' => 'Productores Musicales', 'description' => 'Comunidad privada para productores: mezclas, feedback y colaboraciones.',
                'visibility' => 'private', 'members_count' => 2400, 'posts_count' => 860, 'art' => 'waves', 'is_member' => false, 'category' => 'Música'],
        ];
    }

    public static function notifications(): array
    {
        $u = self::users();
        $art = static fn (string $a) => 'assets/img/demo/' . $a . '.svg';

        return [
            ['id' => 1, 'type' => 'like', 'actor' => $u['luciana.foto'], 'text' => 'le gustó tu publicación', 'excerpt' => 'Nuevo set de tipografías para el proyecto…', 'thumb' => $art('orbs'), 'created_at' => self::ago(4), 'read' => false],
            ['id' => 2, 'type' => 'follow_request', 'actor' => $u['diego.runs'], 'text' => 'solicitó seguirte', 'excerpt' => null, 'thumb' => null, 'created_at' => self::ago(25), 'read' => false],
            ['id' => 3, 'type' => 'comment', 'actor' => $u['mateo.dev'], 'text' => 'comentó tu publicación', 'excerpt' => '“Ese contraste entre el morado y el azul funciona increíble.”', 'thumb' => $art('horizon'), 'created_at' => self::ago(48), 'read' => false],
            ['id' => 4, 'type' => 'mention', 'actor' => $u['nico.design'], 'text' => 'te mencionó en un hilo', 'excerpt' => '“@valentina.rios tiene el mejor criterio para sistemas de diseño.”', 'thumb' => null, 'created_at' => self::ago(95), 'read' => false],
            ['id' => 5, 'type' => 'follow', 'actor' => $u['camila.lab'], 'text' => 'comenzó a seguirte', 'excerpt' => null, 'thumb' => null, 'created_at' => self::ago(300), 'read' => true],
            ['id' => 6, 'type' => 'reply', 'actor' => $u['isa.reads'], 'text' => 'respondió a tu comentario', 'excerpt' => '“Totalmente de acuerdo, lo agrego a la lista del club.”', 'thumb' => null, 'created_at' => self::ago(1600), 'read' => true],
            ['id' => 7, 'type' => 'like', 'actor' => $u['sofia.travel'], 'text' => 'y 128 personas más les gustó tu foto', 'excerpt' => null, 'thumb' => $art('aurora'), 'created_at' => self::ago(3000), 'read' => true],
            ['id' => 8, 'type' => 'follow', 'actor' => $u['andres.music'], 'text' => 'comenzó a seguirte', 'excerpt' => null, 'thumb' => null, 'created_at' => self::ago(6200), 'read' => true],
        ];
    }

    public static function conversations(): array
    {
        $u = self::users();
        $me = 'valentina.rios';
        $m = static fn (string $from, string $body, int $minutes) => ['from' => $from, 'body' => $body, 'created_at' => self::ago($minutes)];

        return [
            ['id' => 1, 'user' => $u['nico.design'], 'unread' => 2, 'online' => true, 'messages' => [
                $m('nico.design', '¡Hola! ¿Viste las nuevas exploraciones del sistema de diseño?', 42),
                $m($me, 'Sí, me encantaron. La versión con la cuadrícula en perspectiva es mi favorita.', 40),
                $m('nico.design', 'Pensé lo mismo. ¿Te parece si la revisamos mañana con el equipo?', 12),
                $m('nico.design', 'Te comparto el archivo esta noche.', 11),
            ]],
            ['id' => 2, 'user' => $u['mateo.dev'], 'unread' => 0, 'online' => true, 'messages' => [
                $m($me, '¿Puedo citar tu hilo de arquitectura en mi charla?', 300),
                $m('mateo.dev', '¡Claro! Solo menciona la fuente. Si quieres te paso diapositivas.', 290),
                $m($me, 'Perfecto, gracias.', 288),
            ]],
            ['id' => 3, 'user' => $u['luciana.foto'], 'unread' => 0, 'online' => false, 'messages' => [
                $m('luciana.foto', 'Gracias por compartir mi foto. ¿Qué cámara usas tú?', 1440),
                $m($me, 'Una analógica de los 80 y paciencia infinita.', 1400),
            ]],
            ['id' => 4, 'user' => $u['sofia.travel'], 'unread' => 0, 'online' => false, 'messages' => [
                $m('sofia.travel', 'Te recomiendo ir en marzo, el clima es perfecto.', 4320),
            ]],
            ['id' => 5, 'user' => $u['camila.lab'], 'unread' => 0, 'online' => true, 'messages' => [
                $m($me, '¿A qué hora es la transmisión?', 8000),
                $m('camila.lab', 'Mañana a las 7 p. m. Te espero.', 7900),
            ]],
        ];
    }
}
