<?php
declare(strict_types=1);

namespace Trevix\Services;

use Trevix\Core\ActionError;
use Trevix\Models\User;

/**
 * Capas de una historia con foto o video: textos, stickers de GIPHY, ubicación, encuesta de 2 opciones,
 * menciones y enlace. Llegan desde el editor (JSON) y se validan aquí antes de guardarse en stories.overlays.
 * Posición x/y es el centro de la capa en fracciones del lienzo (0–1); scale y rotation (radianes) son libres
 * dentro de unos límites para que ninguna capa tape la historia entera ni quede fuera de la vista.
 */
final class StoryOverlays
{
    public const FILTERS = [
        'vivid'    => 'Vívido',
        'warm'     => 'Cálido',
        'cool'     => 'Frío',
        'mono'     => 'Blanco y negro',
        'vintage'  => 'Vintage',
        'fade'     => 'Suave',
        'dramatic' => 'Dramático',
        // Alpha 1.2 (también en los videos de la cámara de reels).
        'smooth'   => 'Rejuvenecer',
        'glow'     => 'Brillo',
        'rose'     => 'Rosa',
        'neon'     => 'Neón',
        'noir'     => 'Noir',
    ];

    public const TEXT_COLORS = ['#FFFFFF', '#000000', '#F43F5E', '#F59E0B', '#FACC15', '#10B981', '#22D3EE', '#3B82F6', '#8B5CF6', '#EC4899'];
    /** Efectos del texto (Alpha 1.7 suma soft, outline, shadow, pop, glitch y gradient). */
    public const TEXT_STYLES = ['plain', 'box', 'soft', 'neon', 'outline', 'shadow', 'pop', 'glitch', 'gradient'];

    /** Fuentes del texto: clave => familia (la web las aloja en assets/fonts; la app usa las mismas). */
    public const TEXT_FONTS = [
        'display'    => 'Space Grotesk',
        'classic'    => 'Inter',
        'strong'     => 'Bebas Neue',
        'impact'     => 'Anton',
        'script'     => 'Pacifico',
        'cursive'    => 'Dancing Script',
        'elegant'    => 'Playfair Display',
        'marker'     => 'Permanent Marker',
        'hand'       => 'Caveat',
        'retro'      => 'Lobster',
        'typewriter' => 'Courier Prime',
    ];

    /** Máximo de capas por tipo (y en total). */
    private const LIMITS = ['text' => 5, 'sticker' => 5, 'location' => 1, 'poll' => 1, 'mention' => 5, 'link' => 1];
    private const MAX_TOTAL = 12;

    /**
     * @param mixed $raw JSON (texto) o lista ya decodificada
     * @return array{items: list<array>, mentions: list<int>} capas listas para guardar e ids a quienes avisar
     */
    public static function normalize(int $uid, mixed $raw): array
    {
        if (is_string($raw)) {
            $raw = trim($raw);
            if ($raw === '' || $raw === '[]') {
                return ['items' => [], 'mentions' => []];
            }
            if (strlen($raw) > 20000) {
                throw ActionError::field('overlays', 'La historia tiene demasiados elementos.');
            }
            $raw = json_decode($raw, true);
        }
        if ($raw === null || $raw === []) {
            return ['items' => [], 'mentions' => []];
        }
        if (!is_array($raw) || !array_is_list($raw)) {
            throw ActionError::field('overlays', 'Los elementos de la historia no son válidos.');
        }
        if (count($raw) > self::MAX_TOTAL) {
            throw ActionError::field('overlays', t('Una historia admite hasta {n} elementos.', ['n' => self::MAX_TOTAL]));
        }

        $items = [];
        $mentions = [];
        $counts = [];
        foreach ($raw as $layer) {
            if (!is_array($layer)) {
                throw ActionError::field('overlays', 'Los elementos de la historia no son válidos.');
            }
            $type = (string) ($layer['type'] ?? '');
            if (!isset(self::LIMITS[$type])) {
                throw ActionError::field('overlays', 'Hay un elemento de un tipo desconocido.');
            }
            $counts[$type] = ($counts[$type] ?? 0) + 1;
            if ($counts[$type] > self::LIMITS[$type]) {
                throw ActionError::field('overlays', match ($type) {
                    'poll'     => 'Una historia lleva una sola encuesta.',
                    'link'     => 'Una historia lleva un solo enlace.',
                    'location' => 'Una historia lleva una sola ubicación.',
                    default    => 'Hay demasiados elementos del mismo tipo.',
                });
            }

            $item = ['type' => $type] + self::placement($layer) + match ($type) {
                'text'     => self::text($layer),
                'sticker'  => self::sticker($layer),
                'location' => self::location($layer),
                'poll'     => self::poll($layer),
                'mention'  => self::mention($uid, $layer),
                'link'     => self::link($layer),
            };
            if ($type === 'mention' && $item['user_id'] !== $uid && !in_array($item['user_id'], $mentions, true)) {
                $mentions[] = $item['user_id'];
            }
            $items[] = $item;
        }
        return ['items' => $items, 'mentions' => $mentions];
    }

    public static function filter(string $value): ?string
    {
        $value = trim($value);
        return isset(self::FILTERS[$value]) ? $value : null;
    }

    /**
     * Colores derivados del texto, iguales a los de la app: 'end' es el final del degradado (tono girado 60°;
     * en blancos, negros y grises, un violeta) y 'dark' la sombra del efecto 3D (45 % de la luminosidad).
     *
     * @return array{end: string, dark: string}
     */
    public static function textShades(string $hex): array
    {
        $rgb = sscanf(ltrim($hex, '#'), '%02x%02x%02x');
        [$r, $g, $b] = array_map(static fn ($v): float => (int) $v / 255, $rgb ?: [255, 255, 255]);
        $max = max($r, $g, $b);
        $min = min($r, $g, $b);
        $l = ($max + $min) / 2;
        $d = $max - $min;
        $s = $d == 0.0 ? 0.0 : $d / (1 - abs(2 * $l - 1));
        $h = 0.0;
        if ($d != 0.0) {
            $h = match ($max) {
                $r      => 60 * fmod(($g - $b) / $d + 6, 6),
                $g      => 60 * (($b - $r) / $d + 2),
                default => 60 * (($r - $g) / $d + 4),
            };
        }
        $end = $s < 0.15 ? ($l > 0.5 ? '#A78BFA' : '#7C3AED') : self::hsl(fmod($h + 60, 360), $s, $l);
        return ['end' => $end, 'dark' => self::hsl($h, $s, $l * 0.45)];
    }

    private static function hsl(float $h, float $s, float $l): string
    {
        $c = (1 - abs(2 * $l - 1)) * $s;
        $x = $c * (1 - abs(fmod($h / 60, 2) - 1));
        $m = $l - $c / 2;
        [$r, $g, $b] = match (intdiv((int) $h, 60)) {
            0       => [$c, $x, 0],
            1       => [$x, $c, 0],
            2       => [0, $c, $x],
            3       => [0, $x, $c],
            4       => [$x, 0, $c],
            default => [$c, 0, $x],
        };
        return sprintf('#%02X%02X%02X', (int) round(($r + $m) * 255), (int) round(($g + $m) * 255), (int) round(($b + $m) * 255));
    }

    private static function placement(array $layer): array
    {
        $num = static fn (string $key, float $default, float $min, float $max): float =>
            is_numeric($layer[$key] ?? null) ? round(max($min, min($max, (float) $layer[$key])), 4) : $default;
        return [
            'x'        => $num('x', 0.5, 0.0, 1.0),
            'y'        => $num('y', 0.5, 0.0, 1.0),
            'scale'    => $num('scale', 1.0, 0.3, 4.0),
            'rotation' => $num('rotation', 0.0, -M_PI, M_PI),
        ];
    }

    private static function text(array $layer): array
    {
        $text = Guard::cleanText((string) ($layer['text'] ?? ''));
        if ($text === '' || mb_strlen($text) > 150) {
            throw ActionError::field('overlays', 'Cada texto debe tener entre 1 y 150 caracteres.');
        }
        $color = strtoupper((string) ($layer['color'] ?? ''));
        $style = (string) ($layer['style'] ?? 'plain');
        $font = (string) ($layer['font'] ?? 'display');
        return [
            'text'  => $text,
            'color' => in_array($color, self::TEXT_COLORS, true) ? $color : '#FFFFFF',
            'style' => in_array($style, self::TEXT_STYLES, true) ? $style : 'plain',
            'font'  => isset(self::TEXT_FONTS[$font]) ? $font : 'display',
        ];
    }

    private static function sticker(array $layer): array
    {
        try {
            $gif = Giphy::resolve((string) ($layer['gif_id'] ?? ''), 'sticker');
        } catch (ActionError $e) {
            throw ActionError::field('overlays', $e->fields['gif'] ?? 'Uno de los stickers ya no está disponible.');
        }
        if ($gif === null) {
            throw ActionError::field('overlays', 'Elige un sticker.');
        }
        return ['gif_id' => $gif['gif_id'], 'url' => $gif['gif_url'], 'width' => $gif['gif_width'], 'height' => $gif['gif_height']];
    }

    private static function location(array $layer): array
    {
        $name = Guard::singleLine((string) ($layer['name'] ?? ''), 80);
        if ($name === null || mb_strlen($name) < 2) {
            throw ActionError::field('overlays', 'Escribe el nombre del lugar.');
        }
        return ['name' => $name];
    }

    private static function poll(array $layer): array
    {
        $question = Guard::singleLine((string) ($layer['question'] ?? ''), 80);
        $options = array_values(array_map(
            static fn ($o): ?string => is_string($o) ? Guard::singleLine($o, 25) : null,
            is_array($layer['options'] ?? null) ? $layer['options'] : []
        ));
        if ($question === null) {
            throw ActionError::field('overlays', 'Escribe la pregunta de la encuesta.');
        }
        if (count($options) !== 2 || in_array(null, $options, true)) {
            throw ActionError::field('overlays', 'La encuesta necesita dos opciones (hasta 25 caracteres cada una).');
        }
        if (mb_strtolower($options[0]) === mb_strtolower($options[1])) {
            throw ActionError::field('overlays', 'Las dos opciones de la encuesta deben ser distintas.');
        }
        return ['question' => $question, 'options' => $options];
    }

    private static function mention(int $uid, array $layer): array
    {
        $username = mb_strtolower(ltrim(trim((string) ($layer['username'] ?? '')), '@'));
        $user = preg_match('/^[a-z0-9_.]{3,30}$/', $username) ? User::findByUsername($username) : null;
        if ($user === null || ($user['status'] ?? 'active') !== 'active' || User::blockedBetween($uid, (int) $user['id'])) {
            throw ActionError::field('overlays', t('No encontramos a @{username}.', ['username' => $username !== '' ? $username : '…']));
        }
        return ['user_id' => (int) $user['id'], 'username' => (string) $user['username']];
    }

    private static function link(array $layer): array
    {
        $url = trim((string) ($layer['url'] ?? ''));
        if ($url !== '' && !preg_match('#^https?://#i', $url)) {
            $url = 'https://' . $url;
        }
        $parts = parse_url($url);
        $host = is_array($parts) ? (string) ($parts['host'] ?? '') : '';
        if (strlen($url) > 300 || !filter_var($url, FILTER_VALIDATE_URL) || !in_array(strtolower((string) ($parts['scheme'] ?? '')), ['http', 'https'], true)
            || !str_contains($host, '.') || isset($parts['user']) || isset($parts['pass'])) {
            throw ActionError::field('overlays', 'El enlace no es válido. Usa una dirección como https://ejemplo.com');
        }
        $label = Guard::singleLine((string) ($layer['label'] ?? ''), 30);
        return ['url' => $url, 'label' => $label ?? preg_replace('/^www\./i', '', $host)];
    }
}
