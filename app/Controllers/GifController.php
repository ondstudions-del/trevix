<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Services\Giphy;

/** api/gifs.php?kind=gif|sticker&q=&offset= — búsqueda en GIPHY para el selector de GIF (assets/js/gifs.js). */
final class GifController extends Controller
{
    public function api(): void
    {
        $user = $this->requireUser();
        if (Request::isPost()) {
            header('Allow: GET');
            Response::json(['ok' => false, 'error' => 'Método no permitido.'], 405);
        }
        $result = $this->attempt(
            static fn () => Giphy::search(
                (int) $user['id'],
                Request::queryIn('kind', array_keys(Giphy::KINDS), 'gif'),
                (string) Request::query('q', ''),
                max(0, (int) Request::query('offset', '0'))
            ),
            url('feed.php')
        );
        Response::json(['ok' => true, 'items' => $result['items'], 'next' => $result['next']]);
    }
}
