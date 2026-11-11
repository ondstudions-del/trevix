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
    ];

    public const TEXT_COLORS = ['#FFFFFF', '#000000', '#F43F5E', '#F59E0B', '#FACC15', '#10B981', '#22D3EE', '#3B82F6', '#8B5CF6', '#EC4899'];
    public const TEXT_STYLES = ['plain', 'box', 'neon'];

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
        return [
            'text'  => $text,
            'color' => in_array($color, self::TEXT_COLORS, true) ? $color : '#FFFFFF',
            'style' => in_array($style, self::TEXT_STYLES, true) ? $style : 'plain',
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
