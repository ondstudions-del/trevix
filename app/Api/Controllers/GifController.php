<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Reply;
use Trevix\Core\Request;
use Trevix\Services\Giphy;

/** GIF y stickers de GIPHY (la app busca a través del servidor; la clave no sale de TREVIX). */
final class GifController extends ApiController
{
    /** GET /gifs/{gif|sticker}?q=&offset= — sin texto: tendencias. */
    public function search(string $kind): never
    {
        $result = Giphy::search($this->uid(), $kind, Request::query('q'), max(0, (int) Request::query('offset')));
        Reply::ok($result['items'], ['next' => $result['next'] !== null ? ['offset' => $result['next']] : null]);
    }
}
