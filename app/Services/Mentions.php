<?php
declare(strict_types=1);

namespace Trevix\Services;

use Trevix\Core\Config;
use Trevix\Models\Follow;
use Trevix\Models\User;

/** Menciones @usuario en textos, con la misma regla que usa format_post_body() para enlazarlas. */
final class Mentions
{
    /** @return list<string> nombres de usuario únicos, en minúsculas y en orden de aparición. */
    public static function extract(?string $text): array
    {
        if ($text === null || !str_contains($text, '@')) {
            return [];
        }
        preg_match_all('/(?<![\w.])@([a-z0-9_.]{3,30})/i', $text, $matches);
        $names = [];
        foreach ($matches[1] as $name) {
            $name = rtrim(mb_strtolower($name), '.');
            if (strlen($name) >= 3) {
                $names[$name] = true;
            }
        }
        return array_slice(array_keys($names), 0, (int) Config::get('app.limits.mentions_per_text', 10));
    }

    /**
     * Personas para completar una @mención (web y API). Sin texto: amistades, cuentas que sigue y seguidores.
     * Con texto: primero esas mismas que coinciden y después el resto de TREVIX (la búsqueda de personas).
     *
     * @return list<array{id:int, username:string, display_name:string, avatar_path:?string, is_verified:bool, relation:?string}>
     */
    public static function suggest(int $userId, string $term, int $limit = 8): array
    {
        $term = mb_substr(ltrim(trim($term), '@'), 0, 30);
        if ($term !== '' && !preg_match('/^[\p{L}\p{N}._ ]+$/u', $term)) {
            return [];
        }
        $items = Follow::mentionCandidates($userId, $term, $limit);
        if ($term !== '' && count($items) < $limit) {
            $seen = array_column($items, 'id');
            foreach (User::search($userId, $term, 1, $limit)['users'] as $u) {
                if (count($items) >= $limit) {
                    break;
                }
                if ((int) $u['id'] === $userId || in_array((int) $u['id'], $seen, true)) {
                    continue;
                }
                $items[] = [
                    'id' => (int) $u['id'], 'username' => (string) $u['username'], 'display_name' => (string) $u['display_name'],
                    'avatar_path' => $u['avatar_path'] ?? null, 'is_verified' => (int) ($u['is_verified'] ?? 0), 'relation' => null,
                ];
            }
        }
        return array_map(static fn (array $u): array => ['is_verified' => (bool) $u['is_verified']] + $u, $items);
    }

    /** Texto corto de la relación para la lista («Amistad», «Sigues», «Te sigue»). */
    public static function relationLabel(?string $relation): ?string
    {
        return match ($relation) {
            'friend'    => t('Amistad'),
            'following' => t('Sigues'),
            'follower'  => t('Te sigue'),
            default     => null,
        };
    }
}
