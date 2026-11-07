<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Reply;
use Trevix\Core\ActionError;
use Trevix\Core\Auth;
use Trevix\Core\Config;
use Trevix\Core\Request;

/** Base de los controladores de la API v1. */
abstract class ApiController
{
    /** Persona autenticada con su token (las rutas «user» ya lo garantizan). */
    protected function user(): array
    {
        return Auth::user() ?? throw new ActionError('Inicia sesión para continuar.', 401);
    }

    protected function uid(): int
    {
        return (int) $this->user()['id'];
    }

    /** Paginación de feeds: ?before=ID (orden reciente) o ?page=N (otros órdenes). */
    protected function paging(string $limitKey = 'feed_page', int $default = 15): array
    {
        return [
            'before' => max(0, (int) Request::query('before')),
            'page'   => $this->pageNumber(),
            'limit'  => $this->limit($limitKey, $default),
        ];
    }

    protected function pageNumber(): int
    {
        return max(1, min(1000, (int) Request::query('page', '1')));
    }

    /** ?limit= acotado entre 1 y el tamaño de página configurado. */
    protected function limit(string $limitKey, int $default): int
    {
        $max = (int) Config::get('app.limits.' . $limitKey, $default);
        $limit = (int) Request::query('limit', (string) $max);
        return max(1, min($max, $limit));
    }

    /** meta.next para listas paginadas por número de página. */
    protected function nextPage(bool $hasMore): array
    {
        return ['next' => $hasMore ? ['page' => $this->pageNumber() + 1] : null];
    }

    protected function created(mixed $data): never
    {
        Reply::ok($data, [], 201);
    }

    protected function notFound(string $message): never
    {
        throw new ActionError($message, 404);
    }
}
