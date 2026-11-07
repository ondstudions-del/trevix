<?php
declare(strict_types=1);

use Trevix\Core\Config;
use Trevix\Core\ErrorHandler;
use Trevix\Core\Response;
use Trevix\Core\Session;

define('BASE_PATH', dirname(__DIR__));
define('APP_PATH', BASE_PATH . '/app');

spl_autoload_register(static function (string $class): void {
    $prefix = 'Trevix\\';
    if (!str_starts_with($class, $prefix)) {
        return;
    }
    $file = APP_PATH . '/' . str_replace('\\', '/', substr($class, strlen($prefix))) . '.php';
    if (is_file($file)) {
        require $file;
    }
});

require APP_PATH . '/Helpers/functions.php';

Config::load(BASE_PATH . '/config');

date_default_timezone_set((string) Config::get('app.timezone', 'UTC'));
mb_internal_encoding('UTF-8');

ErrorHandler::register((bool) Config::get('app.debug', false));
Response::sendSecurityHeaders();

// La API v1 se autentica con tokens Bearer: sin cookie de sesión y con su propio modo mantenimiento.
if (!defined('TREVIX_API')) {
    Session::start();
    Trevix\Middleware\MaintenanceMode::handle();
}
