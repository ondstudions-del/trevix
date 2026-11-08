<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Models\RateLimit;
use Trevix\Models\User;
use Trevix\Services\Guard;

/** api/mentions.php?q= : cuentas para completar una @mención (las mismas reglas de visibilidad que la búsqueda). */
final class MentionController extends Controller
{
    public function suggest(): void
    {
        $user = $this->requireUser();
        $q = mb_substr(ltrim(trim((string) Request::query('q')), '@'), 0, 30);
        if ($q === '' || !preg_match('/^[\p{L}\p{N}._]+$/u', $q)) {
            Response::json(['ok' => true, 'items' => []]);
        }
        $key = 'user:' . (int) $user['id'];
        $this->attempt(static fn () => Guard::rateLimit('mention_search', $key, 'Vas demasiado rápido. Espera {min} min.'), url('feed.php'));
        RateLimit::hit('mention_search', $key);

        $items = array_map(static fn (array $u): array => [
            'username'     => $u['username'],
            'display_name' => $u['display_name'],
            'avatar'       => !empty($u['avatar_path']) ? url($u['avatar_path']) : null,
            'is_verified'  => !empty($u['is_verified']),
        ], User::search((int) $user['id'], $q, 1, 6)['users']);
        Response::json(['ok' => true, 'items' => $items]);
    }
}
