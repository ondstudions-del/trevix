<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use Trevix\Core\Lang;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Middleware\VerifyCsrf;

/** Cambia el idioma de la interfaz (cookie y, con sesión, la cuenta) y vuelve a la página anterior. */
final class LangController extends Controller
{
    public function change(): never
    {
        $this->onlyPost();
        VerifyCsrf::handle();
        $locale = Request::text('locale');
        if (!Lang::isSupported($locale)) {
            Response::abort(400, 'Elige un idioma disponible.');
        }
        Lang::remember($locale);
        if (Request::wantsJson()) {
            Response::json(['ok' => true, 'locale' => $locale]);
        }
        $this->redirectBack(url('index.php'));
    }
}
