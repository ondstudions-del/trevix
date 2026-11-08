<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Reply;
use Trevix\Core\Request;
use Trevix\Services\Geo;

/** Nombre del lugar para la ubicación actual al publicar. */
final class GeoController extends ApiController
{
    /** GET /geo/reverse?lat=&lng= */
    public function reverse(): never
    {
        Reply::ok(Geo::reverse($this->uid(), Request::query('lat'), Request::query('lng')));
    }
}
