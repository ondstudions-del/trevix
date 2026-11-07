<?php
declare(strict_types=1);

namespace Trevix\Middleware;

use Trevix\Core\Auth;
use Trevix\Core\Config;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;

final class Authenticate
{
    public static function handle(): void
    {
        if (Auth::check() || Config::previewEnabled()) {
            return;
        }
        if (!Request::isPost()) {
            Session::set('_intended', (string) ($_SERVER['REQUEST_URI'] ?? ''));
        }
        Session::flash('info', 'Inicia sesión para continuar.');
        Response::redirect(url('login.php'));
    }
}
