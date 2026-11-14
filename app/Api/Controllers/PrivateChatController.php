<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Input;
use Trevix\Api\Reply;
use Trevix\Core\ActionError;
use Trevix\Models\Conversation;
use Trevix\Models\PrivateChat;
use Trevix\Services\PrivateChatService;

/**
 * Chats privados con PIN (ver PrivateChatService). Los chats se pasan a privados con POST /conversations/bulk
 * (action=private|unprivate) y se abren escribiendo el PIN en el buscador (GET /conversations?q=PIN).
 */
final class PrivateChatController extends ApiController
{
    /** GET /me/private-chats — si hay PIN, si el desbloqueo enviado vale y cuántos chats privados hay (solo desbloqueado). */
    public function show(): never
    {
        $uid = $this->uid();
        $unlocked = $this->privateUnlocked();
        Reply::ok([
            'has_pin'  => PrivateChat::hasPin($uid),
            'unlocked' => $unlocked,
            'count'    => $unlocked ? count(Conversation::privateIds($uid)) : null,
            'pin_min'  => 4,
            'pin_max'  => 8,
        ]);
    }

    /** POST /me/private-chats/unlock {pin} — desbloqueo para abrir un chat privado desde otro sitio. */
    public function unlock(): never
    {
        $token = PrivateChatService::unlock($this->uid(), Input::str('pin'));
        Reply::ok(['token' => $token, 'expires_in' => PrivateChatService::TOKEN_TTL]);
    }

    /** PUT /me/private-chats/pin {pin, pin_confirmation, current_pin?} — crea el PIN o lo cambia (con el actual). */
    public function pin(): never
    {
        $uid = $this->uid();
        $had = PrivateChat::hasPin($uid);
        $token = PrivateChatService::setPin($uid, Input::str('pin'), Input::str('pin_confirmation'), Input::str('current_pin'));
        Reply::ok([
            'token'      => $token,
            'expires_in' => PrivateChatService::TOKEN_TTL,
            'message'    => $had ? 'Cambiaste el PIN de tus chats privados.' : 'Creaste el PIN de tus chats privados.',
        ]);
    }

    /** POST /me/private-chats/reset {password, pin, pin_confirmation} — olvidé mi PIN: vacía los chats privados y crea uno nuevo. */
    public function reset(): never
    {
        $token = PrivateChatService::reset($this->user(), Input::str('password', false), Input::str('pin'), Input::str('pin_confirmation'));
        Reply::ok([
            'token'      => $token,
            'expires_in' => PrivateChatService::TOKEN_TTL,
            'message'    => 'Vaciaste tus chats privados y creaste un PIN nuevo.',
        ]);
    }

    /**
     * POST /me/private-chats/export {password?} — con el desbloqueo o con la contraseña de la cuenta (si se olvidó el
     * PIN): los chats privados con sus mensajes; los cifrados van con epoch y texto cifrado para descifrarlos en la app.
     */
    public function export(): never
    {
        $user = $this->user();
        PrivateChatService::exportAllowed($user, $this->privateUnlocked(), Input::str('password', false));
        Reply::ok(PrivateChatService::export((int) $user['id']));
    }

    /** POST /me/private-chats/empty — vacía y quita de la lista todos los chats privados (solo desbloqueado). */
    public function clear(): never
    {
        $uid = $this->unlockedUid();
        $count = PrivateChatService::emptyAll($uid);
        Reply::ok(['count' => $count, 'message' => $count > 0 ? 'Vaciaste tus chats privados.' : 'No tenías chats privados.']);
    }

    /** DELETE /me/private-chats — desactiva: los chats privados vuelven a la bandeja y se borra el PIN (solo desbloqueado). */
    public function disable(): never
    {
        $count = PrivateChatService::disable($this->unlockedUid());
        Reply::ok([
            'count'   => $count,
            'message' => 'Desactivaste los chats privados: tus chats volvieron a la bandeja.',
            'unread'  => Conversation::unreadCount($this->uid()),
        ]);
    }

    private function unlockedUid(): int
    {
        if (!$this->privateUnlocked()) {
            throw new ActionError('Escribe tu PIN en el buscador de los chats para abrir tus chats privados.', 423);
        }
        return $this->uid();
    }
}
