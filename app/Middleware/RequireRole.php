<?php
declare(strict_types=1);

namespace Trevix\Middleware;

use Trevix\Core\Auth;
use Trevix\Core\Config;
use Trevix\Core\Response;
use Trevix\Core\Session;

final class RequireRole
{
    public static function handle(string $minimumRole): void
    {
        if (Auth::check()) {
            if (Auth::hasRole($minimumRole)) {
                return;
            }
            Response::abort(403, 'No tienes permisos para acceder a esta sección.');
        }

        if (Config::previewEnabled()) {
            return;
        }

        Session::flash('info', 'Inicia sesión con una cuenta autorizada.');
        Response::redirect(url('login.php'));
    }
}
