<?php
declare(strict_types=1);

use Trevix\Core\Config;
use Trevix\Core\Csrf;

/** Escapa cualquier valor para imprimirlo en HTML (texto o atributos). */
function e(mixed $value): string
{
    return htmlspecialchars((string) $value, ENT_QUOTES | ENT_SUBSTITUTE | ENT_HTML5, 'UTF-8');
}

/** Ruta base del proyecto (permite instalarlo en un subdirectorio de Apache). */
function base_path(): string
{
    static $base = null;
    if ($base !== null) {
        return $base;
    }

    $configured = (string) Config::get('app.url', '');
    if ($configured !== '') {
        return $base = rtrim($configured, '/');
    }

    $base = '';
    $docRoot = str_replace('\\', '/', (string) (realpath($_SERVER['DOCUMENT_ROOT'] ?? '') ?: ''));
    $root = str_replace('\\', '/', (string) (realpath(BASE_PATH) ?: BASE_PATH));

    if ($docRoot !== '' && stripos($root, $docRoot) === 0) {
        $relative = trim(substr($root, strlen($docRoot)), '/');
        if ($relative !== '') {
            $base = '/' . implode('/', array_map('rawurlencode', explode('/', $relative)));
        }
    }
    return $base;
}

function url(string $path = '', array $query = []): string
{
    // Archivos de catálogos externos (audio y portadas de Audius o Free To Use, GIF de GIPHY).
    $url = str_starts_with($path, 'https://') ? $path : base_path() . '/' . ltrim($path, '/');
    $query = array_filter($query, static fn ($v) => $v !== null && $v !== '');
    return $query ? $url . '?' . http_build_query($query) : $url;
}

/**
 * URL absoluta para enlaces enviados por correo. En producción se toma de app.url;
 * sin esa configuración (desarrollo) se usa el host de la petición.
 */
function absolute_url(string $path = '', array $query = []): string
{
    $url = url($path, $query);
    if (preg_match('#^https?://#i', $url)) {
        return $url;
    }
    $host = (string) ($_SERVER['HTTP_HOST'] ?? 'localhost');
    if (!preg_match('/^[a-z0-9.-]+(:\d+)?$/i', $host)) {
        $host = 'localhost';
    }
    return (Trevix\Core\Request::isHttps() ? 'https://' : 'http://') . $host . $url;
}

/** URL de un recurso estático con versión para invalidar caché. */
function asset(string $path): string
{
    $file = BASE_PATH . '/assets/' . ltrim($path, '/');
    $version = is_file($file) ? (string) filemtime($file) : '1';
    return url('assets/' . ltrim($path, '/')) . '?v=' . $version;
}

function csrf_field(): string
{
    return Csrf::field();
}

/** Icono SVG de Lucide alojado en assets/icons, insertado en línea. */
function icon(string $name, string $class = '', ?string $label = null): string
{
    static $cache = [];

    if (!array_key_exists($name, $cache)) {
        $cache[$name] = '';
        $file = BASE_PATH . '/assets/icons/' . $name . '.svg';
        if (preg_match('/^[a-z0-9-]+$/', $name) && is_file($file)) {
            $svg = (string) file_get_contents($file);
            if (preg_match('#<svg[^>]*>(.*)</svg>#s', $svg, $m)) {
                $cache[$name] = trim((string) preg_replace('/\s+/', ' ', $m[1]));
            }
        }
    }

    $a11y = $label !== null
        ? 'role="img" aria-label="' . e($label) . '"'
        : 'aria-hidden="true" focusable="false"';

    return '<svg class="icon ' . e($class) . '" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" '
        . 'stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" ' . $a11y . '>'
        . $cache[$name] . '</svg>';
}

/** Une clases CSS condicionales: cx('btn', ['is-active' => $active]). */
function cx(string|array ...$parts): string
{
    $classes = [];
    foreach ($parts as $part) {
        if (is_string($part)) {
            $classes[] = $part;
            continue;
        }
        foreach ($part as $class => $enabled) {
            if ($enabled) {
                $classes[] = $class;
            }
        }
    }
    return implode(' ', array_filter($classes));
}

/**
 * Atributos para controles cuya lógica de servidor llega en una fase posterior:
 * el control queda deshabilitado y explica cuándo estará disponible.
 */
function pending(int $phase): string
{
    return 'disabled aria-disabled="true" data-tooltip="Disponible en la Fase ' . $phase . '"';
}

/** Atributos de accesibilidad para un campo con error de validación del servidor. */
function invalid_attrs(array $errors, string $field, string $inputId): string
{
    return isset($errors[$field]) ? ' aria-invalid="true" aria-describedby="error-' . e($inputId) . '"' : '';
}

/** Mensaje de error del servidor para un campo; el mismo contenedor lo reutiliza la validación del cliente. */
function field_error(array $errors, string $field, string $inputId): string
{
    $message = $errors[$field] ?? '';
    return '<p class="field__error" id="error-' . e($inputId) . '" data-error-for="' . e($inputId) . '"'
        . ($message === '' ? ' hidden' : '') . '>' . e($message) . '</p>';
}

function initials(string $name): string
{
    $words = preg_split('/\s+/u', trim($name)) ?: [];
    $letters = '';
    foreach (array_slice($words, 0, 2) as $word) {
        $letters .= mb_substr($word, 0, 1);
    }
    return mb_strtoupper($letters !== '' ? $letters : '#');
}

/** Avatar del usuario: imagen subida o iniciales con un degradado estable. */
function avatar(array $user, string $size = 'md', string $extra = ''): string
{
    $classes = cx('avatar', 'avatar--' . $size, $extra);

    if (!empty($user['avatar_path'])) {
        return '<img class="' . e($classes) . '" src="' . e(url($user['avatar_path'])) . '" alt="" loading="lazy" decoding="async">';
    }

    $tone = (crc32((string) ($user['username'] ?? '')) % 6) + 1;
    return '<span class="' . e($classes . ' avatar--tone-' . $tone) . '" aria-hidden="true">'
        . e(initials((string) ($user['display_name'] ?? $user['username'] ?? ''))) . '</span>';
}

function profile_url(array $user): string
{
    return url('profile.php', ['u' => $user['username'] ?? '']);
}

/** Ilustración por defecto de una comunidad (portada e icono), estable según su slug. */
function community_art(array $community): string
{
    $arts = ['orbs', 'aurora', 'horizon', 'peaks', 'city', 'waves'];
    $art = (string) ($community['art'] ?? '');
    return in_array($art, $arts, true) ? $art : $arts[crc32((string) ($community['slug'] ?? '')) % count($arts)];
}

/** Icono de la comunidad: imagen subida o iniciales sobre su degradado. $size: '' | 'lg' | 'xl'. */
function community_icon(array $community, string $size = ''): string
{
    $classes = cx('community-icon', $size !== '' ? 'community-icon--' . $size : '');
    if (!empty($community['avatar_path'])) {
        return '<img class="' . e($classes . ' community-icon--img') . '" src="' . e(url($community['avatar_path'])) . '" alt="" loading="lazy" decoding="async">';
    }
    return '<span class="' . e($classes . ' community-icon--' . community_art($community)) . '" aria-hidden="true">'
        . e(initials((string) ($community['name'] ?? ''))) . '</span>';
}

function community_cover(array $community): string
{
    return !empty($community['cover_path'])
        ? url($community['cover_path'])
        : url('assets/img/demo/' . community_art($community) . '.svg');
}

function community_url(array $community, array $query = []): string
{
    return url('community.php', ['c' => $community['slug'] ?? ''] + $query);
}

/**
 * Relación de quien mira con $user: la real (clave "relation", de Follow::withRelations)
 * o la de los datos de demostración ("relationship": none | following | friend | requested).
 *
 * @return array{following: bool, requested: bool, follows_you: bool}
 */
function relation_of(array $user): array
{
    if (isset($user['relation'])) {
        return $user['relation'];
    }
    $demo = $user['relationship'] ?? 'none';
    return [
        'following'   => in_array($demo, ['following', 'friend'], true),
        'requested'   => $demo === 'requested',
        'follows_you' => $demo === 'friend',
    ];
}

function compact_number(int $n): string
{
    if ($n < 1000) {
        return (string) $n;
    }
    [$value, $suffix] = $n < 1_000_000 ? [$n / 1000, ' mil'] : [$n / 1_000_000, ' M'];
    $formatted = number_format(floor($value * 10) / 10, 1, ',', '.');
    return rtrim(rtrim($formatted, '0'), ',') . $suffix;
}

function plural(int $n, string $one, string $many): string
{
    return $n === 1 ? $one : $many;
}

function spanish_months(bool $short = false): array
{
    return $short
        ? ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sept', 'oct', 'nov', 'dic']
        : ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
}

function time_ago(string $datetime): string
{
    $timestamp = strtotime($datetime) ?: time();
    $diff = time() - $timestamp;

    return match (true) {
        $diff < 60     => 'ahora',
        $diff < 3600   => intdiv($diff, 60) . ' min',
        $diff < 86400  => intdiv($diff, 3600) . ' h',
        $diff < 604800 => intdiv($diff, 86400) . ' d',
        default        => (int) date('j', $timestamp) . ' ' . spanish_months(true)[(int) date('n', $timestamp) - 1]
            . (date('Y', $timestamp) !== date('Y') ? ' ' . date('Y', $timestamp) : ''),
    };
}

function full_date(string $datetime, bool $withTime = true): string
{
    $timestamp = strtotime($datetime) ?: time();
    $date = (int) date('j', $timestamp) . ' de ' . spanish_months()[(int) date('n', $timestamp) - 1] . ' de ' . date('Y', $timestamp);
    return $withTime ? $date . ', ' . date('H:i', $timestamp) : $date;
}

/** Etiqueta <time> accesible con fecha relativa y fecha completa en el título. */
function time_tag(string $datetime): string
{
    $timestamp = strtotime($datetime) ?: time();
    return '<time datetime="' . e(date(DATE_ATOM, $timestamp)) . '" title="' . e(full_date($datetime)) . '">'
        . e(time_ago($datetime)) . '</time>';
}

/**
 * Convierte el texto de una publicación en HTML seguro: primero escapa todo
 * y después enlaza URLs, #hashtags y @menciones.
 */
function format_post_body(string $text): string
{
    $html = e($text);

    $html = (string) preg_replace_callback(
        '~(https?://[^\s<]+)|(?<![\w&])#([\p{L}\p{N}_]{1,50})|(?<![\w.])@([a-z0-9_.]{3,30})~iu',
        static function (array $m): string {
            if (!empty($m[1])) {
                $link = rtrim($m[1], '.,!?;:)');
                $tail = substr($m[1], strlen($link));
                $label = preg_replace('~^https?://(www\.)?~i', '', $link);
                return '<a href="' . $link . '" target="_blank" rel="noopener noreferrer nofollow ugc">' . $label . '</a>' . $tail;
            }
            if (!empty($m[2])) {
                return '<a class="hashtag" href="' . e(url('explore.php', ['tag' => $m[2]])) . '">#' . $m[2] . '</a>';
            }
            $username = rtrim($m[3], '.');
            $tail = substr($m[3], strlen($username));
            return '<a class="mention" href="' . e(url('profile.php', ['u' => mb_strtolower($username)])) . '">@' . $username . '</a>' . $tail;
        },
        $html
    );

    return nl2br($html, false);
}

/** Canción disponible (Song::cardsFor) con las rutas que usa assets/js/music.js. */
function song_client(array $song): array
{
    return [
        'id'          => (int) $song['id'],
        'title'       => $song['title'],
        'featuring'   => $song['featuring'],
        'is_explicit' => (bool) $song['is_explicit'],
        'duration'    => (int) $song['duration'],
        'src'         => url($song['src']),
        'cover'       => !empty($song['cover']) ? url($song['cover']) : null,
        'source'      => $song['source'] ?? 'trevix',
        'source_label' => $song['source_label'] ?? 'TREVIX',
        'artist'      => ['username' => $song['artist']['username'], 'display_name' => $song['artist']['display_name']],
    ];
}

/** Configuración expuesta al JavaScript del cliente (sin datos sensibles). */
function client_config(): string
{
    $uploads = Config::get('app.uploads');
    return (string) json_encode([
        'baseUrl'   => base_path(),
        'csrfToken' => Csrf::token(),
        'preview'   => Config::previewEnabled(),
        'limits'    => Config::get('app.limits'),
        'uploads'   => [
            'maxFiles' => $uploads['max_files_per_post'],
            'image'    => ['maxBytes' => $uploads['image']['max_bytes'], 'mimes' => $uploads['image']['mimes']],
            'video'    => ['maxBytes' => $uploads['video']['max_bytes'], 'mimes' => $uploads['video']['mimes']],
            'audio'    => [
                'maxBytes'   => $uploads['audio']['max_bytes'],
                'minSeconds' => $uploads['audio']['min_seconds'],
                'maxSeconds' => $uploads['audio']['max_seconds'],
                'extensions' => $uploads['audio']['extensions'],
            ],
            'voice'    => [
                'maxBytes'   => $uploads['voice']['max_bytes'],
                'minSeconds' => $uploads['voice']['min_seconds'],
                'maxSeconds' => $uploads['voice']['max_seconds'],
            ],
        ],
    ], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT);
}
