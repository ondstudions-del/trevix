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
            'title'       => t('TREVIX — Conecta. Comparte. Descubre.'),
            'description' => t('TREVIX es la red social que une fotos, videos, historias, hilos y comunidades en un solo lugar.'),
            'previewUrl'  => Config::previewEnabled() ? url('feed.php') : url('login.php'),
        ], 'layouts/public');
    }

    public function legal(): void
    {
        $documents = [
            'terminos'   => t('Términos y condiciones'),
            'privacidad' => t('Política de privacidad'),
            'cookies'    => t('Política de cookies'),
            'reembolsos' => t('Política de reembolsos'),
        ];
        $doc = Request::queryIn('doc', array_keys($documents), 'terminos');

        $this->render('pages/legal', [
            'title'       => $documents[$doc] . ' · TREVIX',
            'description' => t('{document} de TREVIX, la red social de {owner}.', ['document' => $documents[$doc], 'owner' => Config::get('app.legal.owner')]),
            'doc'         => $doc,
            'documents'   => $documents,
            'legal'       => Config::get('app.legal'),
        ], 'layouts/public');
    }
}
