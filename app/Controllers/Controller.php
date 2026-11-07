<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use Trevix\Core\ActionError;
use Trevix\Core\Auth;
use Trevix\Core\Config;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Core\View;
use Trevix\Data\DemoData;
use Trevix\Middleware\VerifyCsrf;
use Trevix\Models\Community;
use Trevix\Models\Follow;
use Trevix\Models\Hashtag;
use Trevix\Services\Guard;

abstract class Controller
{
    /** Vista previa = modo demostración activo y sin sesión real. */
    protected function isPreview(): bool
    {
        return !Auth::check() && Config::previewEnabled();
    }

    protected function viewer(): ?array
    {
        return Auth::user() ?? ($this->isPreview() ? DemoData::viewer() : null);
    }

    /** Datos del panel derecho (tendencias, sugerencias y comunidades). */
    protected function asideData(): array
    {
        $preview = $this->isPreview();
        return [
            'trends'      => $preview ? DemoData::trends() : Hashtag::trending(5),
            'suggestions' => $preview ? DemoData::suggestions() : Follow::suggestions((int) Auth::id(), 3),
            'communities' => $preview ? array_slice(DemoData::communities(), 0, 3) : Community::suggestions((int) Auth::id(), 3),
        ];
    }

    /**
     * Rechaza en el servidor cualquier envío a una función cuya lógica llega en una fase posterior,
     * para que ningún formulario aparente funcionar.
     */
    protected function rejectWritesUntil(int $phase): void
    {
        if (Request::isPost()) {
            VerifyCsrf::handle();
            Response::abort(503, 'Esta acción se habilitará en la Fase ' . $phase . '.');
        }
    }

    /** Endpoints de la API: cualquier método distinto de POST responde 405. */
    protected function onlyPost(): void
    {
        if (!Request::isPost()) {
            header('Allow: POST');
            Response::abort(405, 'Este endpoint solo acepta solicitudes POST.');
        }
    }

    /** Usuario con sesión real para acciones que escriben; la vista previa nunca puede guardar datos. */
    protected function requireUser(): array
    {
        $user = Auth::user();
        if ($user === null) {
            if (Request::wantsJson()) {
                Response::json(['ok' => false, 'error' => 'Inicia sesión para continuar.'], 401);
            }
            Session::flash('info', 'Inicia sesión para guardar cambios.');
            Response::redirect(url('login.php'));
        }
        return $user;
    }

    /** Si la configuración exige correo verificado, bloquea publicar, comentar, escribir y crear hasta confirmarlo. */
    protected function requireVerifiedEmail(array $user, string $fallback): void
    {
        $this->attempt(static fn () => Guard::verifiedEmail($user), $fallback);
    }

    /**
     * Ejecuta una acción de un servicio compartido con la API. Si lanza ActionError se responde como
     * cualquier otro error de la web (JSON o aviso con redirección a la página anterior).
     */
    protected function attempt(callable $action, string $fallback): mixed
    {
        try {
            return $action();
        } catch (ActionError $e) {
            if ($e->retryAfter !== null && !headers_sent()) {
                header('Retry-After: ' . $e->retryAfter);
            }
            $this->fail($e->getMessage(), $e->status, $fallback);
        }
    }

    /** Vuelve a la página anterior solo si es de este mismo sitio; si no, a $fallback. */
    protected function redirectBack(string $fallback): never
    {
        $referer = (string) ($_SERVER['HTTP_REFERER'] ?? '');
        $host = $referer !== '' ? parse_url($referer, PHP_URL_HOST) : null;
        $ownHost = parse_url(absolute_url(), PHP_URL_HOST);
        if (is_string($host) && is_string($ownHost) && strcasecmp($host, $ownHost) === 0) {
            Response::redirect($referer);
        }
        Response::redirect($fallback);
    }

    /** Responde un error en JSON (peticiones con JavaScript) o como aviso flash con redirección. */
    protected function fail(string $message, int $status, string $fallback): never
    {
        if (Request::wantsJson()) {
            Response::json(['ok' => false, 'error' => $message], $status);
        }
        Session::flash('error', $message);
        $this->redirectBack($fallback);
    }

    /** Texto multilínea escrito por el usuario: normaliza saltos y quita caracteres de control. */
    protected function cleanText(string $text): string
    {
        return Guard::cleanText($text);
    }

    /** Para cargas parciales (paginación con JavaScript) se devuelve solo el fragmento HTML. */
    protected function isPartial(): bool
    {
        return Request::query('partial') === '1';
    }

    /** Parámetros de paginación de los feeds (cursor ?before= o ?page=). */
    protected function paging(): array
    {
        return [
            'before' => (int) Request::query('before'),
            'page'   => (int) Request::query('page', '1'),
            'limit'  => (int) Config::get('app.limits.feed_page', 15),
        ];
    }

    /** Responde solo el fragmento de la lista (sin layout) y termina. */
    protected function renderList(array $list, ?string $endText = null): never
    {
        View::partial('post-list', $list + ['viewer' => $this->viewer(), 'endText' => $endText]);
        exit;
    }

    /** Publicaciones y URL de la página siguiente para el parcial post-list. */
    protected function listData(array $result, string $page, array $query): array
    {
        return [
            'posts'   => $result['posts'],
            'nextUrl' => $result['next'] !== null ? url($page, $query + $result['next']) : null,
        ];
    }

    /** Guarda errores y datos del formulario para mostrarlos tras la redirección (patrón PRG). */
    protected function backWithErrors(string $to, array $errors, array $old = []): never
    {
        Session::set('_errors', $errors);
        Session::set('_old', $old);
        Response::redirect($to);
    }

    protected function render(string $view, array $data = [], string $layout = 'layouts/app'): void
    {
        View::render($view, $data + [
            'viewer'    => $this->viewer(),
            'isPreview' => $this->isPreview(),
        ], $layout);
    }
}
