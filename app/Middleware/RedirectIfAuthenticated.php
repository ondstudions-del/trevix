<?php
declare(strict_types=1);

namespace Trevix\Middleware;

use Trevix\Core\Auth;
use Trevix\Core\Response;

final class RedirectIfAuthenticated
{
    public static function handle(): void
    {
        if (Auth::check()) {
            Response::redirect(url('feed.php'));
        }
    }
}
