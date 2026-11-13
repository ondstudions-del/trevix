<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Input;
use Trevix\Api\Kernel;
use Trevix\Api\Reply;
use Trevix\Core\ActionError;
use Trevix\Core\Lang;
use Trevix\Core\Request;
use Trevix\Models\Conversation;
use Trevix\Models\Push;
use Trevix\Models\PushDevice;
use Trevix\Models\RateLimit;
use Trevix\Services\Fcm;
use Trevix\Services\Guard;
use Trevix\Services\PushFeed;

/**
 * Avisos del teléfono. GET me/push devuelve lo nuevo desde los cursores (la app de Android lo consulta al despertar,
 * por Firebase o por su servicio propio, y lo muestra como notificaciones del sistema). Los teléfonos con Firebase
 * Cloud Messaging registran aquí su token para recibir los avisos con la app cerrada.
 */
final class PushController extends ApiController
{
    /**
     * GET /me/push?n=&m=&f=&r= — n: último aviso, m: último mensaje, f: última solicitud, r: fecha de la última
     * reacción revisada. Sin cursores válidos solo devuelve los iniciales (no avisa de nada antiguo).
     */
    public function poll(): never
    {
        $uid = $this->uid();
        $since = (string) Request::query('r');
        if (!PushFeed::validDate($since)) {
            Conversation::markDelivered($uid);
            Reply::ok([], ['cursor' => Push::cursors($uid), 'uid' => $uid]);
        }
        $feed = PushFeed::collect($uid, [
            'n' => (int) Request::query('n'),
            'm' => (int) Request::query('m'),
            'f' => (int) Request::query('f'),
            'r' => $since,
        ]);
        Reply::ok($feed['items'], ['cursor' => $feed['cursor'], 'uid' => $uid]);
    }

    /**
     * POST /me/push/devices {token, platform: android|ios, app_version?} — registra el token de Firebase del teléfono
     * para esta sesión. delivery: «failing» si los últimos envíos a este teléfono fallaron (por ejemplo, la clave de
     * Apple no está en Firebase): la app sigue revisando por su cuenta para no perder avisos.
     */
    public function register(): never
    {
        if (!Fcm::configured()) {
            throw new ActionError('Los avisos por Firebase no están activos en el servidor.', 503);
        }
        $uid = $this->uid();
        Guard::rateLimit('push_register', 'user:' . $uid, 'Demasiados intentos. Inténtalo de nuevo en {min} min.');
        $token = trim(Input::str('token'));
        $platform = Input::str('platform');
        if ($token === '' || strlen($token) > 400 || preg_match('/^[A-Za-z0-9_:\-.]+$/', $token) !== 1) {
            throw ActionError::field('token', 'El token del teléfono no es válido.');
        }
        if (!in_array($platform, PushDevice::PLATFORMS, true)) {
            throw ActionError::field('platform', 'Plataforma no válida.');
        }
        $version = mb_substr(preg_replace('/[^0-9A-Za-z.+\- ]/', '', Input::str('app_version', false)) ?? '', 0, 20);
        $tokenId = (int) (Kernel::token()['id'] ?? 0);
        if ($tokenId < 1) {
            throw new ActionError('Inicia sesión para continuar.', 401);
        }
        RateLimit::hit('push_register', 'user:' . $uid);
        $id = PushDevice::register($uid, $tokenId, $platform, $token, $version !== '' ? $version : null, Lang::locale(), Push::cursors($uid));
        $device = PushDevice::find($id);
        $failing = $device !== null && $device['last_error'] !== null && (int) $device['failures'] >= 2;
        Reply::ok(['registered' => true, 'delivery' => $failing ? 'failing' : 'ok']);
    }

    /** DELETE /me/push/devices {token} — el teléfono deja de recibir avisos de esta cuenta (al cerrar sesión). */
    public function unregister(): never
    {
        $token = trim(Input::str('token'));
        if ($token !== '') {
            PushDevice::remove($this->uid(), $token);
        }
        Reply::ok(['registered' => false]);
    }
}
