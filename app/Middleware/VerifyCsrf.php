<?php
declare(strict_types=1);

namespace Trevix\Middleware;

use Trevix\Core\Csrf;
use Trevix\Core\Request;
use Trevix\Core\Response;

final class VerifyCsrf
{
    public static function handle(): void
    {
        if (in_array(Request::method(), ['GET', 'HEAD', 'OPTIONS'], true)) {
            return;
        }
        if (!Csrf::verify(Csrf::tokenFromRequest())) {
            Response::abort(419, 'Tu sesión expiró o el formulario no es válido. Recarga la página e inténtalo de nuevo.');
        }
    }
}
