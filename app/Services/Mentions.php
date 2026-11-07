<?php
declare(strict_types=1);

namespace Trevix\Services;

use Trevix\Core\Config;

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
}
