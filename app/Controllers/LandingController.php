<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use Trevix\Core\Auth;
use Trevix\Core\Config;
use Trevix\Core\Response;
use Trevix\Core\Request;

final class LandingController extends Controller
{
    public function index(): void
    {
        if (Auth::check()) {
            Response::redirect(url('feed.php'));
        }

        $this->render('pages/landing', [
            'title'       => 'TREVIX — Conecta. Comparte. Descubre.',
            'description' => 'TREVIX es la red social que une fotos, videos, historias, hilos y comunidades en un solo lugar.',
            'previewUrl'  => Config::previewEnabled() ? url('feed.php') : url('login.php'),
        ], 'layouts/public');
    }

    public function legal(): void
    {
        $documents = [
            'terminos'   => 'Términos y condiciones',
            'privacidad' => 'Política de privacidad',
            'cookies'    => 'Política de cookies',
        ];
        $doc = Request::queryIn('doc', array_keys($documents), 'terminos');

        $this->render('pages/legal', [
            'title'       => $documents[$doc] . ' · TREVIX',
            'description' => $documents[$doc] . ' de TREVIX, la red social de ' . Config::get('app.legal.owner') . '.',
            'doc'         => $doc,
            'documents'   => $documents,
            'legal'       => Config::get('app.legal'),
        ], 'layouts/public');
    }
}
