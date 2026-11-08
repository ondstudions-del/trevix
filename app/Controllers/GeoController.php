<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Services\Geo;

/** api/geo.php?lat=&lng= : nombre del lugar para «Usar mi ubicación» del compositor. */
final class GeoController extends Controller
{
    public function reverse(): void
    {
        $user = $this->requireUser();
        if (Request::isPost()) {
            header('Allow: GET');
            Response::json(['ok' => false, 'error' => 'Método no permitido.'], 405);
        }
        $place = $this->attempt(
            static fn () => Geo::reverse((int) $user['id'], Request::query('lat'), Request::query('lng')),
            url('feed.php')
        );
        Response::json(['ok' => true] + $place);
    }
}
