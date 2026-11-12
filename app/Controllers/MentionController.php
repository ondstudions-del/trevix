<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Models\RateLimit;
use Trevix\Services\Guard;
use Trevix\Services\Mentions;

/**
 * api/mentions.php?q= : personas para completar una @mención en publicaciones y comentarios. Con «@» solo
 * (q vacío) devuelve amistades, cuentas que sigues y seguidores; con texto, esas primero y luego el resto.
 */
final class MentionController extends Controller
{
    public function suggest(): void
    {
        $user = $this->requireUser();
        $q = mb_substr(ltrim(trim((string) Request::query('q')), '@'), 0, 30);
        if ($q !== '' && !preg_match('/^[\p{L}\p{N}._]+$/u', $q)) {
            Response::json(['ok' => true, 'items' => []]);
        }
        $key = 'user:' . (int) $user['id'];
        $this->attempt(static fn () => Guard::rateLimit('mention_search', $key, 'Vas demasiado rápido. Espera {min} min.'), url('feed.php'));
        RateLimit::hit('mention_search', $key);

        $items = array_map(static fn (array $u): array => [
            'username'     => $u['username'],
            'display_name' => $u['display_name'],
            'avatar'       => !empty($u['avatar_path']) ? url($u['avatar_path']) : null,
            'is_verified'  => $u['is_verified'],
            'relation'     => Mentions::relationLabel($u['relation']),
        ], Mentions::suggest((int) $user['id'], $q));
        Response::json(['ok' => true, 'items' => $items]);
    }
}
